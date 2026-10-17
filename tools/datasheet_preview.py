#!/usr/bin/env python3
"""Local datasheet preview for a Tiny Tapeout submission.

Reads the two inputs the TT `docs` workflow reads -- `info.yaml` and
`docs/info.md` -- and renders them with toolchain that is already on this
machine: `markdown-it-py` to parse, MiKTeX's `pdflatex` to typeset. Nothing is
downloaded.

    python tools/datasheet_preview.py            # build/preview/datasheet.pdf
    python tools/datasheet_preview.py --html     # HTML only, no LaTeX needed

This is NOT the TT datasheet generator. It is a preview, so wording, tables and
pin assignments can be eyeballed before spending a CI run on them. Layout
deliberately differs from the shipped datasheet, which the `docs` workflow still
produces.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

import yaml
from markdown_it import MarkdownIt

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "build" / "preview"

# Unicode that occurs in the docs, mapped for LaTeX. A character outside this
# table and outside ASCII raises rather than being dropped silently.
UNICODE_LATEX = {
    "\u2014": "---",               # em dash
    "\u2013": "--",                # en dash
    "\u2248": r"$\approx$",
    "\u00b1": r"$\pm$",
    "\u00b7": r"$\cdot$",
    "\u2192": r"$\rightarrow$",
    "\u2264": r"$\leq$",
    "\u2265": r"$\geq$",
    "\u00d7": r"$\times$",
    "\u00b5": r"$\mu$",
    "\u03bc": r"$\mu$",
    "\u2026": "\\ldots{}",
    "\u00a0": "~",                 # nbsp
}

LATEX_SPECIALS = {
    "\\": r"\textbackslash{}",
    "&": r"\&",
    "%": r"\%",
    "$": r"\$",
    "#": r"\#",
    "_": r"\_",
    "{": r"\{",
    "}": r"\}",
    "~": r"\textasciitilde{}",
    "^": r"\textasciicircum{}",
}


class UnmappedCharacter(Exception):
    pass


def latex_escape(text: str) -> str:
    out = []
    for ch in text:
        if ch in UNICODE_LATEX:
            out.append(UNICODE_LATEX[ch])
        elif ord(ch) < 128:
            out.append(LATEX_SPECIALS.get(ch, ch))
        else:
            raise UnmappedCharacter(f"no LaTeX mapping for U+{ord(ch):04X} {ch!r}")
    return "".join(out)


# ---------------------------------------------------------------------------
# markdown -> LaTeX
# ---------------------------------------------------------------------------
# markdown-it hands back a flat token stream; nesting is rebuilt from `level`
# because a table sits inside a list item in docs/info.md, and the LaTeX for
# that has to open the table environment inside \item.
# ---------------------------------------------------------------------------

class Node:
    __slots__ = ("kind", "tag", "payload", "children")

    def __init__(self, kind, tag="", payload=None):
        self.kind = kind
        self.tag = tag
        self.payload = payload
        self.children: list[Node] = []


def block_tree(tokens) -> list[Node]:
    root: list[Node] = []
    # (depth, sink for siblings at this depth)
    stack: list[tuple[int, list[Node]]] = [(0, root)]
    openers: list[Node] = []
    for tok in tokens:
        if tok.type.endswith("_open"):
            node = Node(tok.type[:-5], tok.tag)
            stack[-1][1].append(node)
            openers.append(node)
            stack.append((tok.level + 1, node.children))
        elif tok.type.endswith("_close"):
            while len(stack) > 1 and stack[-1][0] > tok.level:
                stack.pop()
        elif tok.type == "inline":
            stack[-1][1].append(Node("inline", payload=tok.children))
        elif tok.type in ("html_block", "fence", "code_block"):
            text = tok.content.rstrip("\n")
            stack[-1][1].append(Node("verbatim", payload=text))
    return root


def code_latex(text: str) -> str:
    # \ttfamily needs the same escapes, but `^` and `~` are commands here, not
    # characters a backslash can prefix.
    return re.sub(
        r"(\\)|([&%#_{}$])|(\^)|(~)",
        lambda m: (
            r"\textbackslash{}" if m.group(1)
            else "\\" + m.group(2)
            if m.group(2)
            else r"\textasciicircum{}" if m.group(3)
            else r"\textasciitilde{}"
        ),
        text,
    )


def inline_latex(children) -> str:
    parts: list[str] = []
    for tok in children:
        if tok.type == "text":
            parts.append(latex_escape(tok.content))
        elif tok.type == "code_inline":
            parts.append(r"\texttt{" + code_latex(tok.content) + "}")
        elif tok.type == "strong_open":
            parts.append(r"\textbf{")
        elif tok.type == "em_open":
            parts.append(r"\textit{")
        elif tok.type in ("strong_close", "em_close"):
            parts.append("}")
        elif tok.type == "link_open":
            parts.append(r"\url{" + str(tok.attrs.get("href", "")) + "}")
        elif tok.type == "softbreak":
            parts.append(" ")
        elif tok.type == "hardbreak":
            parts.append(r"\\" + " ")
        else:
            parts.append(latex_escape(getattr(tok, "content", "") or ""))
    return "".join(parts)


def table_latex(table: Node, width: str) -> str:
    rows: list[str] = []
    ncol = 0
    for section in table.children:
        for tr in section.children:
            cells = [inline_latex(c.children[0].payload) if c.children else ""
                     for c in tr.children]
            ncol = max(ncol, len(cells))
            rows.append(" & ".join(cells) + r" \\")
        if section.kind == "thead":
            rows.append(r"\midrule")
    spec = width if width else "l" * ncol
    return ("\\begin{center}\\begin{tabular}{" + spec + "}\n\\toprule\n"
            + "\n".join(rows) + "\n\\bottomrule\n\\end{tabular}\\end{center}")


def nodes_to_latex(nodes) -> str:
    out: list[str] = []
    for n in nodes:
        if n.kind == "heading":
            cmd = "subsection" if int(n.tag[1:]) >= 3 else "section"
            out.append(f"\\{cmd}*{{{nodes_to_latex(n.children)}}}")
        elif n.kind == "paragraph":
            out.append(nodes_to_latex(n.children))
        elif n.kind == "ordered_list":
            out.append("\\begin{enumerate}\n" + nodes_to_latex(n.children) + "\\end{enumerate}")
        elif n.kind == "bullet_list":
            out.append("\\begin{itemize}\n" + nodes_to_latex(n.children) + "\\end{itemize}")
        elif n.kind == "list_item":
            blocks = [b for b in nodes_to_latex(n.children).split("\n\n") if b.strip()]
            head, *rest = blocks or [""]
            # A tabular cannot float inside \item, so the tables nested in list
            # items are emitted flush-left instead of in a `center` block.
            tail = "\n".join(rest)
            out.append("\\item " + head + ("\n" + tail if tail else ""))
        elif n.kind == "table":
            out.append(table_latex(n, ""))
        elif n.kind == "inline":
            out.append(inline_latex(n.payload))
        elif n.kind == "verbatim":
            out.append("\\begin{quote}\\ttfamily " + latex_escape(n.payload) + "\\end{quote}")
    return "\n\n".join(out)


# ---------------------------------------------------------------------------
# document assembly
# ---------------------------------------------------------------------------

PREAMBLE = r"""\documentclass[11pt]{article}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage{lmodern}
\usepackage[a4paper,margin=2.1cm,headheight=15pt]{geometry}
\usepackage{amssymb}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{enumitem}
\usepackage{upquote}
\usepackage{array}
\usepackage{fancyhdr}
\usepackage{hyperref}
\usepackage{titlesec}
\titleformat{\section}{\large\bfseries}{}{0pt}{}[\vspace{1pt}\titlerule]
\titlespacing*{\section}{0pt}{14pt}{6pt}
\setlist{itemsep=3pt,topsep=4pt,parsep=0pt}
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\textsf{\small TT submission preview}}
\fancyhead[R]{\textsf{\small __SHUTTLE__}}
\fancyfoot[C]{\textsf{\small \thepage}}
\renewcommand{\headrulewidth}{0.4pt}
"""


def pinout_tables(pinout: dict) -> str:
    groups = [("ui", "Digital input"), ("uo", "Digital output"), ("uio", "Bidirectional")]
    blocks = []
    for prefix, label in groups:
        rows = [(k, v) for k, v in pinout.items() if k.startswith(f"{prefix}[") and str(v).strip()]
        if not rows:
            continue
        lines = [f"\\textbf{{{prefix}}} & \\textbf{{{label}}} " + r"\\" + "\n" + r"\midrule"]
        for name, desc in rows:
            idx = re.search(r"\[(\d+)\]", name).group(1)
            lines.append(f"{prefix}[{idx}] & {latex_escape(str(desc))} " + r"\\")
        blocks.append(
            "\\begin{longtable}{>{\\raggedright\\arraybackslash}p{2.2cm}"
            ">{\\raggedright\\arraybackslash}p{12.4cm}}\n\\toprule\n"
            + "\n".join(lines) + "\n\\bottomrule\n\\end{longtable}"
        )
    if not blocks:
        return ""
    return "\\section*{Pin assignment}\n\n" + "\n".join(blocks)


TITLE_BLOCK = r"""\begin{center}
{\LARGE\bfseries __TITLE__}\\[3pt]
{\large __AUTHOR__}\\[5pt]
\emph{__DESCRIPTION__}\\[3pt]
\textsf{\small __FACTS__}
\end{center}
\vspace{2pt}\hrule\vspace{6pt}
"""


def build_tex(md_text: str, project: dict, pinout: dict, shuttle: str) -> str:
    tokens = MarkdownIt().enable("table").parse(md_text)
    body = nodes_to_latex(block_tree(tokens))
    facts = r" \textbullet{} ".join(latex_escape(str(x)) for x in (
        project.get("language"),
        project.get("tiles") and f"{project['tiles']} tile",
        project.get("top_module") and f"top module {project['top_module']}",
        project.get("clock_hz") and f"up to {int(project['clock_hz']) // 10**6} MHz",
    ) if x)
    head = (TITLE_BLOCK
            .replace("__TITLE__", latex_escape(str(project.get("title", "Untitled"))))
            .replace("__AUTHOR__", latex_escape(str(project.get("author", ""))))
            .replace("__DESCRIPTION__", latex_escape(str(project.get("description", ""))))
            .replace("__FACTS__", facts))
    return (
        PREAMBLE.replace("__SHUTTLE__", latex_escape(shuttle))
        + "\\begin{document}\n" + head + body + "\n"
        + pinout_tables(pinout) + "\n\\end{document}\n"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--html", action="store_true", help="render HTML only, skip LaTeX")
    ap.add_argument("--md", default=str(REPO / "docs" / "info.md"))
    ap.add_argument("--yaml", default=str(REPO / "info.yaml"))
    ap.add_argument("--shuttle", default="@ttsky26d")
    args = ap.parse_args()

    md_text = Path(args.md).read_text(encoding="utf-8")
    meta = yaml.safe_load(Path(args.yaml).read_text(encoding="utf-8"))
    project, pinout = meta["project"], meta.get("pinout", {})

    OUT.mkdir(parents=True, exist_ok=True)
    html = (
        "<!doctype html><meta charset=utf-8><title>" + str(project.get("title"))
        + "</title><style>body{font:15px/1.5 system-ui;max-width:46rem;margin:3rem auto;"
        "padding:0 1rem}h2{border-bottom:1px solid #ccc;padding-bottom:.2rem}"
        "table{border-collapse:collapse;margin:.6rem 0}th,td{border:1px solid #bbb;"
        "padding:.25rem .5rem;text-align:left}code{background:#f4f4f4;padding:0 .2rem}"
        "</style>" + MarkdownIt().enable("table").render(md_text)
    )
    (OUT / "datasheet.html").write_text(html, encoding="utf-8")
    print("html   ", OUT / "datasheet.html")
    if args.html:
        return 0

    try:
        tex = build_tex(md_text, project, pinout, args.shuttle)
    except UnmappedCharacter as exc:
        print(f"latex  SKIPPED: {exc}\n         add a mapping in {__file__}")
        return 1
    (OUT / "datasheet.tex").write_text(tex, encoding="utf-8")
    for _ in range(2):
        r = subprocess.run(
            ["pdflatex", "-interaction=nonstopmode", "-halt-on-error", "datasheet.tex"],
            cwd=OUT, capture_output=True, text=True,
        )
        if r.returncode:
            tail = [l for l in (r.stdout or "").splitlines() if l.strip()][-12:]
            print("latex  FAILED:\n  " + "\n  ".join(tail))
            return 1
    print("latex  ", OUT / "datasheet.pdf")
    return 0


if __name__ == "__main__":
    sys.exit(main())
