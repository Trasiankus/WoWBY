"""Tiny Lua 5.1 lexer + scope resolver (enough for WoW addon code), used by tools/split_core.py.

resolve(src) -> list of Ref(pos, end, name, decl) for every NAME token that is a variable reference or declaration:
  decl = ("top", name)   the chunk's top-level local `name` (declared at depth 0)
         ("inner", id)   a local inside some function/block
         None            a global (free name)
Field names (a.b, a:b), table-constructor keys ({ key = …}), goto/labels are not variables and are skipped.
Declarations are reported too (Ref.is_decl). `local a, b = expr` makes a/b visible only AFTER the expression list.
"""
import re

KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local",
            "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
TOKEN_RX = re.compile(r"""
  (?P<ws>\s+)
| (?P<comment>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|--[^\n]*)
| (?P<lstring>\[(?P<leq>=*)\[.*?\](?P=leq)\])
| (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
| (?P<number>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
| (?P<name>[A-Za-z_][A-Za-z0-9_]*)
| (?P<op>\.\.\.|\.\.|==|~=|<=|>=|::|[-+*/%^\#<>=(){}\[\];:,.])
""", re.S | re.X)


class Tok:
    __slots__ = ("kind", "text", "pos", "end")

    def __init__(self, kind, text, pos, end):
        self.kind, self.text, self.pos, self.end = kind, text, pos, end

    def __repr__(self):
        return "%s:%r@%d" % (self.kind, self.text, self.pos)


def lex(src):
    out, i = [], 0
    while i < len(src):
        m = TOKEN_RX.match(src, i)
        if not m:
            raise SyntaxError("lex error at %d: %r" % (i, src[i:i + 20]))
        k = m.lastgroup
        if k in ("ceq", "leq"):
            k = "comment" if m.group("comment") else "lstring"
        if k not in ("ws", "comment"):
            kind = "string" if k in ("string", "lstring") else k
            if kind == "name" and m.group(0) in KEYWORDS:
                kind = "kw"
            out.append(Tok(kind, m.group(0), m.start(), m.end()))
        i = m.end()
    return out


class Ref:
    __slots__ = ("pos", "end", "name", "decl", "is_decl", "depth", "assign")

    def __init__(self, tok, decl, is_decl, depth, assign=False):
        self.pos, self.end, self.name = tok.pos, tok.end, tok.text
        self.decl, self.is_decl, self.depth, self.assign = decl, is_decl, depth, assign


ENDS_EXPR = {"name", "string", "number"}


def _expr_end(tok, prev):
    """True when `tok` cannot continue an expression that `prev` ended (a new statement starts)."""
    if prev is None:
        return False
    prev_ends = prev.kind in ENDS_EXPR or prev.text in (")", "]", "}", "end", "true", "false", "nil", "...")
    if not prev_ends:
        return False
    if tok.kind == "name":
        return True
    return tok.kind == "kw" and tok.text in ("local", "if", "for", "while", "return", "do", "repeat", "end", "until",
                                             "else", "elseif", "function", "break", "goto")


def resolve(src):
    toks = lex(src)
    refs = []
    scopes = [{}]          # name -> decl id ; scope 0 = chunk top level
    kinds = ["top"]        # block kind per scope
    uid = [0]

    def declare(tok, is_top):
        uid[0] += 1
        d = ("top", tok.text) if is_top else ("inner", uid[0])
        scopes[-1][tok.text] = d
        refs.append(Ref(tok, d, True, len(scopes) - 1))
        return d

    def lookup(name):
        for sc in reversed(scopes):
            if name in sc:
                return sc[name]
        return None

    pending = []           # [(names_tokens, depth_at_decl, paren_depth)] for `local a, b = expr`
    brace = []             # stack of '{' / '(' / '[' with table-constructor flag
    i, n = 0, len(toks)
    prev = None
    skip_name = False      # the next `function NAME` is a `local function NAME` (already declared)
    while i < n:
        t = toks[i]
        # finish a pending `local a, b = …` when the expression list ended (statement boundary at the same nesting)
        if (pending and len(brace) == pending[-1][2] and (_expr_end(t, prev) or t.text == ";")
                and len(scopes) - 1 == pending[-1][1]):
            names = pending.pop()[0]
            for nt in names:
                declare(nt, len(scopes) == 1)
        if t.kind == "kw":
            if t.text == "local":
                nt = toks[i + 1]
                if nt.text == "function":                       # local function NAME (params) … end
                    declare(toks[i + 2], len(scopes) == 1)
                    skip_name = True
                    prev = t; i += 1                            # continue AT the `function` keyword
                    continue
                names, j = [], i + 1
                while j < n and toks[j].kind == "name":
                    names.append(toks[j])
                    if j + 1 < n and toks[j + 1].text == ",":
                        j += 2
                    else:
                        j += 1
                        break
                # attribs <const> not in 5.1
                if j < n and toks[j].text == "=":
                    pending.append((names, len(scopes) - 1, len(brace)))
                    prev = toks[j]; i = j + 1
                else:                                           # `local a, b` (no value): visible now
                    for nt in names:
                        declare(nt, len(scopes) == 1)
                    prev = names[-1]; i = j
                continue
            if t.text == "function":
                # function NAME[.f|:m](params)  or anonymous function(params)
                j = i + 1
                method = False
                if toks[j].kind == "name":                      # named: first name is a variable reference
                    ref_tok = toks[j]
                    if not skip_name:                           # (`local function NAME` was declared already)
                        d = lookup(ref_tok.text)
                        refs.append(Ref(ref_tok, d, False, len(scopes) - 1, assign=(toks[j + 1].text == "(")))
                    skip_name = False
                    j += 1
                    while toks[j].text in (".", ":"):
                        method = method or toks[j].text == ":"
                        j += 2
                assert toks[j].text == "(", toks[j]
                params, j = [], j + 1
                while toks[j].text != ")":
                    if toks[j].kind == "name":
                        params.append(toks[j])
                    j += 1
                scopes.append({}); kinds.append("function")
                if method:
                    uid[0] += 1; scopes[-1]["self"] = ("inner", uid[0])
                for pt in params:
                    declare(pt, False)
                prev = toks[j]; i = j + 1
                continue
            if t.text in ("do", "then", "repeat"):
                scopes.append({}); kinds.append(t.text)
            elif t.text == "elseif":
                scopes.pop(); kinds.pop()                        # closes the `then` block; a new `then` follows
            elif t.text == "else":
                scopes.pop(); kinds.pop(); scopes.append({}); kinds.append("else")
            elif t.text == "end":
                scopes.pop(); kinds.pop()
            elif t.text == "until":
                # `until cond` still sees the repeat block's locals: pop after the condition — approximate by
                # keeping the scope until the statement ends (next statement start)
                kinds[-1] = "until"
            elif t.text == "for":
                # for a, b in … do  /  for i = … do : loop vars live in the do-block
                j, names = i + 1, []
                while toks[j].kind == "name":
                    names.append(toks[j]); j += 1
                    if toks[j].text == ",":
                        j += 1
                # scan to the matching `do` (at bracket depth 0) resolving the header expressions in the outer scope
                depth = 0
                k = j
                while not (toks[k].text == "do" and depth == 0):
                    if toks[k].text in ("(", "[", "{"):
                        depth += 1
                    elif toks[k].text in (")", "]", "}"):
                        depth -= 1
                    k += 1
                header = toks[j:k]
                # resolve names in the header
                for hi, ht in enumerate(header):
                    if ht.kind == "name" and not (hi > 0 and header[hi - 1].text in (".", ":")):
                        refs.append(Ref(ht, lookup(ht.text), False, len(scopes) - 1))
                scopes.append({}); kinds.append("do")
                for nt in names:
                    declare(nt, False)
                prev = toks[k]; i = k + 1
                continue
            prev = t; i += 1
            continue
        if t.kind == "op":
            if t.text in ("(", "["):
                brace.append(t.text)
            elif t.text == "{":
                brace.append("{")
            elif t.text in (")", "]", "}"):
                if brace:
                    brace.pop()
            prev = t; i += 1
            continue
        if t.kind == "name":
            # `until` ends when a new statement starts
            if kinds[-1] == "until" and _expr_end(t, prev):
                scopes.pop(); kinds.pop()
            is_field = prev is not None and prev.text in (".", ":") or (prev is not None and prev.text == "goto")
            nxt = toks[i + 1] if i + 1 < n else None
            is_key = (brace and brace[-1] == "{" and prev is not None and prev.text in ("{", ",", ";")
                      and nxt is not None and nxt.text == "=")
            if not is_field and not is_key:
                assign = nxt is not None and nxt.text in ("=", ",") and _stmt_start(prev)
                refs.append(Ref(t, lookup(t.text), False, len(scopes) - 1, assign=assign))
            prev = t; i += 1
            continue
        prev = t; i += 1
    return refs, toks


def _stmt_start(prev):
    return prev is None or prev.kind in ("name", "string", "number") or prev.text in (")", "]", "}", "end", "do",
                                                                                         "then", "else", "=", ";")
