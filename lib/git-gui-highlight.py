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
# The lines of one request are lexed together as a single document, so
# multi-line constructs (block comments, multi-line strings) keep state across
# lines. git-gui sends a diff's post-image and pre-image as separate requests,
# each coherent source in file order, so the state is meaningful.
import hashlib
import sys
from collections import OrderedDict

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


def spans_for_doc(lines, lexer):
    """Lex the lines as one document so multi-line constructs keep state across
    lines, yielding (lineidx, col, length, class) spans. A token value can
    straddle newlines (e.g. a block comment), so it is split on '\\n' and the
    line index / column advance accordingly. Columns track each line's original
    characters; the newline itself contributes no column."""
    text = '\n'.join(lines)
    nlines = len(lines)
    idx = 0
    col = 0
    for ttype, value in lex(text, lexer):
        cls = classify(ttype)
        parts = value.split('\n')
        for k, part in enumerate(parts):
            if k > 0:
                idx += 1
                col = 0
            if part and cls is not None and idx < nlines:
                yield (idx, col, len(part), cls)
            col += len(part)


def compute_spans(path, lines):
    """All spans for a batch (one coherent image). Unknown file type -> none."""
    try:
        lexer = get_lexer_for_filename(path)
    except ClassNotFound:
        return []
    try:
        return list(spans_for_doc(lines, lexer))
    except Exception:
        return []  # never let a lexer hiccup drop the batch


# Warm LRU cache keyed by the request content (path + lines fully determine the
# spans). Lets rescans, re-selected files, and prefetched diffs return without
# re-lexing. 256 entries keeps memory trivial while covering a session's worth
# of revisited diffs.
_CACHE = OrderedDict()
_CACHE_MAX = 256


def cached_spans(path, lines):
    key = hashlib.sha1('\x00'.join([path] + lines).encode('utf-8', 'replace')).digest()
    spans = _CACHE.get(key)
    if spans is None:
        spans = compute_spans(path, lines)
        _CACHE[key] = spans
        if len(_CACHE) > _CACHE_MAX:
            _CACHE.popitem(last=False)
    else:
        _CACHE.move_to_end(key)
    return spans


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

        spans = cached_spans(path, lines)

        out.write('RES %s %d\n' % (reqid, len(spans)))
        for (idx, col, length, cls) in spans:
            out.write('%d %d %d %s\n' % (idx, col, length, cls))
        out.flush()


if __name__ == '__main__':
    main()
