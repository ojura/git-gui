#!/usr/bin/env python3
# Persistent syntax-highlight helper for git-gui's diff viewer.
#
# git-gui spawns this once and keeps it warm, so Pygments (and each lexer) is
# imported a single time rather than per file. It speaks a tiny line-framed,
# UTF-8 protocol over stdin/stdout. Payload lines are read by count, so a line
# of code that happens to look like a protocol header is never misparsed.
#
#   Request:   REQ <reqid> <nlines> <path>\n   then exactly <nlines> code lines
#   Response:  RES <reqid> <nspans>\n          then <nspans> span lines:
#                  <lineidx> <col> <len> <class>\n
#
# <col>/<len> are character offsets within the code line (marker column already
# stripped by git-gui). <class> is one of: kw typ str com num fn pre.
#
# Each line is lexed independently for now. Multi-line constructs (notably C
# block comments and multi-line strings) are therefore highlighted only on
# their first line; full-image lexing is a planned refinement and needs no
# protocol change.
import sys

from pygments import lex
from pygments.lexers import get_lexer_for_filename
from pygments.util import ClassNotFound
from pygments.token import Keyword, Name, Comment, String, Number


def classify(ttype):
    """Map a Pygments token type to one of our short tag classes, or None to
    leave the token at the default foreground. More specific token types are
    tested before their parents, since `ttype in Parent` is true for subtypes."""
    if ttype in Comment.Preproc or ttype in Comment.PreprocFile:
        return 'pre'
    if ttype in Comment:
        return 'com'
    if ttype in Keyword.Type:
        return 'typ'
    if ttype in Keyword:
        return 'kw'
    if ttype in String:
        return 'str'
    if ttype in Number:
        return 'num'
    if ttype in Name.Builtin or ttype in Name.Class:
        return 'typ'
    if ttype in Name.Function:
        return 'fn'
    return None


def spans_for_line(idx, code, lexer):
    """Yield (idx, col, length, class) spans for one line of code. Columns track
    the original string; Pygments appends a newline to its input, so any newline
    inside a token value is dropped (the code line itself has none)."""
    col = 0
    for ttype, value in lex(code, lexer):
        value = value.replace('\n', '')
        if not value:
            continue
        cls = classify(ttype)
        if cls is not None:
            yield (idx, col, len(value), cls)
        col += len(value)


def main():
    # Force UTF-8 regardless of the parent's locale.
    sys.stdin.reconfigure(encoding='utf-8', errors='replace')
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    inp, out = sys.stdin, sys.stdout
    while True:
        header = inp.readline()
        if not header:
            break  # parent closed the pipe
        header = header.rstrip('\n')
        if not header.startswith('REQ '):
            continue
        parts = header.split(' ', 3)
        if len(parts) < 3:
            continue
        reqid = parts[1]
        try:
            nlines = int(parts[2])
        except ValueError:
            continue
        path = parts[3] if len(parts) > 3 else ''

        lines = []
        for _ in range(nlines):
            l = inp.readline()
            if l.endswith('\n'):
                l = l[:-1]
            lines.append(l)

        spans = []
        try:
            lexer = get_lexer_for_filename(path)
        except ClassNotFound:
            lexer = None
        if lexer is not None:
            for idx, code in enumerate(lines):
                try:
                    spans.extend(spans_for_line(idx, code, lexer))
                except Exception:
                    pass  # a lexer hiccup on one line must not drop the batch

        out.write('RES %s %d\n' % (reqid, len(spans)))
        for (idx, col, length, cls) in spans:
            out.write('%d %d %d %s\n' % (idx, col, length, cls))
        out.flush()


if __name__ == '__main__':
    main()
