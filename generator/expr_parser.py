from typing import Any, TypeAlias, no_type_check

from lark import Lark, Transformer, Tree

Expression: TypeAlias = Tree

# See https://documentation.dcr.design/documentation/engine-expression-language/
grammar = r"""
    expr: expr OP expr -> binary_expr
        | "(" expr ")"
        | _const
        | IDENTIFIER
    OP: "&&"
      | "||"
      | "<"
      | ">"
      | "="
      | "!="
      | "++"
      | "+"
      | "**"
    _const: STRING
          | INT
          | DOUBLE
          | BOOL
          | NULL
    STRING: /"[^"]*"/ 
          | /'[^']*'/
    INT: /-?[0-9]+/
    DOUBLE: /-?[0-9]+\.[0-9]+/
    BOOL.1: "true" 
          | "false"
    IDENTIFIER: /[a-zA-Z_\$][a-zA-Z0-9-_']*/
    NULL.1: "null"

    %import common.WS
    %ignore WS
"""


@no_type_check
class DictTransformer(Transformer):
    def binary_expr(self, children):
        return {
            "lhs": children[0],
            "op": children[1],
            "rhs": children[2],
        }

    def expr(self, children):
        return children[0]

    def OP(self, tok):
        return tok.value

    def IDENTIFIER(self, tok):
        return {"id": tok.value}

    def NULL(self, tok):
        return {}

    def STRING(self, tok):
        return tok.value[1:-1]

    def INT(self, tok):
        return int(tok.value)

    def DOUBLE(self, tok):
        return float(tok.value)

    def BOOL(self, tok):
        return tok.value == "true"


def parse_expr(expr: str) -> Expression:
    # default parser (earley) has dynamic priority which we don't want
    parser = Lark(grammar, parser="lalr", start="expr")
    return parser.parse(expr)


def get_identifiers(expr: Expression) -> set[str]:
    return set(
        map(
            lambda tok: tok.value,
            expr.scan_values(lambda tok: tok.type == "IDENTIFIER"),
        )
    )


def serialize_expr(expr: Expression) -> Any:
    return DictTransformer().transform(expr)
