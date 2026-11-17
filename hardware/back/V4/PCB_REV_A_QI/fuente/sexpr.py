"""S-expression reader/writer for KiCad files (minimal, no external dependencies)."""
import re


class Sym(str):
    """Bare (unquoted) symbol."""


_TOKEN = re.compile(r'\s*(?:(\()|(\))|"((?:[^"\\]|\\.)*)"|([^\s()"]+))', re.S)


def parse(text):
    stack, cur = [], []
    pos = 0
    n = len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m:
            if text[pos:].strip() == "":
                break
            raise ValueError("bad s-expr near %r" % text[pos:pos + 40])
        pos = m.end()
        if m.group(1):
            stack.append(cur)
            cur = []
        elif m.group(2):
            done = cur
            cur = stack.pop()
            cur.append(done)
        elif m.group(3) is not None:
            cur.append(m.group(3).replace('\\"', '"').replace("\\\\", "\\"))
        else:
            tok = m.group(4)
            try:
                cur.append(int(tok) if re.fullmatch(r"-?\d+", tok) else float(tok))
            except ValueError:
                cur.append(Sym(tok))
    assert not stack, "unbalanced"
    return cur[0] if len(cur) == 1 else cur


def find(node, key):
    for it in node:
        if isinstance(it, list) and it and it[0] == key:
            return it
    return None


def find_all(node, key):
    return [it for it in node if isinstance(it, list) and it and it[0] == key]


def fmt_num(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return str(v)
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def q(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def dump(node, indent=0):
    """Serialise nested lists. Strings are quoted unless they are Sym."""
    if not isinstance(node, list):
        if isinstance(node, Sym):
            return str(node)
        if isinstance(node, str):
            return q(node)
        return fmt_num(node)
    parts = [dump(x, indent + 1) for x in node]
    one = "(" + " ".join(parts) + ")"
    if len(one) < 110 and "\n" not in one:
        return one
    pad = "\t" * (indent + 1)
    out = "(" + parts[0]
    for p in parts[1:]:
        out += "\n" + pad + p
    return out + "\n" + "\t" * indent + ")"
