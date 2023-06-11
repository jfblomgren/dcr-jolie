from runtime import Runtime
from math import Math

from .Choreography import EventID

type Expr: BinaryExpr | Identifier | Const
type Operator: string(enum(["&&", "||", "<", ">", "=", "!=", "++", "+", "**"]))
type Const: string | int | double | bool | void

type BinaryExpr {
    lhs: Expr
    op: Operator
    rhs: Expr
}

type Identifier {
    id: EventID
}

type EvaluateExprRequest {
    expr: Expr
    values: undefined
}

interface EvaluatorInterface {
    RequestResponse:
        evaluate(EvaluateExprRequest)(Const)
}


private interface EvalHelperInterface {
    RequestResponse:
        evaluate_binary(EvaluateExprRequest)(Const),
        evaluate_identifier(EvaluateExprRequest)(Const)
}

private service EvalHelper {
    execution: concurrent 

    embed Runtime as Runtime
    embed Math as Math

    inputPort Self {
        location: "local"
        interfaces: EvaluatorInterface, EvalHelperInterface
    }

    outputPort Self {
        interfaces: EvaluatorInterface, EvalHelperInterface
    }

    init {
        getLocalLocation@Runtime()(Self.location)
    }

    main {
        [evaluate(req)(result) {
            if (req.expr instanceof BinaryExpr) {
                evaluate_binary@Self(req)(result)
            } else if (req.expr instanceof Identifier) {
                evaluate_identifier@Self(req)(result)
            } else if (req.expr instanceof Const) {
                result = req.expr
            }
        }]

        [evaluate_binary(req)(result) {
            evaluate@Self({
                expr << req.expr.lhs,
                values << req.values
            })(lhs)
            evaluate@Self({
                expr << req.expr.rhs,
                values << req.values
            })(rhs)
            
            if (req.expr.op == "&&") {
                result = lhs && rhs
            } else if (req.expr.op == "||") {
                result = lhs || rhs
            } else if (req.expr.op == "<") {
                result = lhs < rhs
            } else if (req.expr.op == ">") {
                result = lhs > rhs
            } else if (req.expr.op == "=") {
                result = lhs == rhs
            } else if (req.expr.op == "!=") {
                result = lhs != rhs
            } else if (req.expr.op == "+" || req.expr.op == "++") {
                result = lhs + rhs
            } else if (req.expr.op == "**") {
                pow@Math({
                    base = lhs,
                    exponent = rhs
                })(result)
            }
        }]

        [evaluate_identifier(req)(result) {
            result = req.values.(req.expr.id)
        }]
    }
}

service Evaluator {
    execution: concurrent 

    embed EvalHelper as EvalHelper

    inputPort IP {
        location: "local"
        interfaces: EvaluatorInterface
    }

    main {
        [evaluate(req)(result) {
            evaluate@EvalHelper(req)(result)
        }]
    }
}