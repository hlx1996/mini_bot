#!/usr/bin/env bash
# plugins/calc.sh — /calc <expr>  安全计算器（数学表达式 / 单位换算 / 进制）。
# 使用 python AST 沙箱：只允许字面量 + 算术 + math 模块函数，禁止任何 name lookup。

plugin_calc() {
  local to="$1" key="$2" rest="$3"
  if [[ -z "$rest" ]]; then
    reply_text "$to" "用法：/calc <表达式>
示例：
  /calc 2**32 - 1
  /calc sin(pi/4) + log(e)
  /calc (1.08)**10
支持 +-*/%, **, // ; 函数：sin/cos/tan/asin/acos/atan, log/log2/log10, exp, sqrt, floor/ceil, abs, pi, e, tau"
    return
  fi
  local out
  out=$(python3 -W ignore::DeprecationWarning - "$rest" <<'PY' 2>&1
import sys, ast, math, operator as op
expr = sys.argv[1]

_ALLOWED_BIN = {
  ast.Add: op.add, ast.Sub: op.sub, ast.Mult: op.mul, ast.Div: op.truediv,
  ast.FloorDiv: op.floordiv, ast.Mod: op.mod, ast.Pow: op.pow,
  ast.BitAnd: op.and_, ast.BitOr: op.or_, ast.BitXor: op.xor,
  ast.LShift: op.lshift, ast.RShift: op.rshift,
}
_ALLOWED_UNARY = { ast.UAdd: op.pos, ast.USub: op.neg, ast.Invert: op.invert }
_ALLOWED_NAMES = {
  'pi': math.pi, 'e': math.e, 'tau': math.tau, 'inf': math.inf, 'nan': math.nan,
}
_ALLOWED_FUNCS = {
  k: getattr(math, k) for k in (
    'sin','cos','tan','asin','acos','atan','atan2','sinh','cosh','tanh',
    'log','log2','log10','exp','sqrt','floor','ceil','factorial','gcd',
    'degrees','radians','hypot','pow',
  )
}
_ALLOWED_FUNCS['abs'] = abs
_ALLOWED_FUNCS['round'] = round
_ALLOWED_FUNCS['min'] = min
_ALLOWED_FUNCS['max'] = max
_ALLOWED_FUNCS['sum'] = sum

def evalnode(n):
    if isinstance(n, ast.Expression): return evalnode(n.body)
    if isinstance(n, ast.Constant) and isinstance(n.value, (int, float, complex)):
        return n.value
    if isinstance(n, ast.BinOp) and type(n.op) in _ALLOWED_BIN:
        return _ALLOWED_BIN[type(n.op)](evalnode(n.left), evalnode(n.right))
    if isinstance(n, ast.UnaryOp) and type(n.op) in _ALLOWED_UNARY:
        return _ALLOWED_UNARY[type(n.op)](evalnode(n.operand))
    if isinstance(n, ast.Name):
        if n.id in _ALLOWED_NAMES: return _ALLOWED_NAMES[n.id]
        raise ValueError(f"未授权符号：{n.id}")
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name):
        fn = _ALLOWED_FUNCS.get(n.func.id)
        if not fn: raise ValueError(f"未授权函数：{n.func.id}")
        return fn(*[evalnode(a) for a in n.args])
    if isinstance(n, ast.Tuple):
        return tuple(evalnode(e) for e in n.elts)
    if isinstance(n, ast.List):
        return [evalnode(e) for e in n.elts]
    raise ValueError(f"不允许的节点：{type(n).__name__}")

try:
    tree = ast.parse(expr, mode='eval')
    r = evalnode(tree)
    if isinstance(r, float):
        if r.is_integer(): print(int(r))
        else: print(f"{r:.10g}")
    else:
        print(r)
except Exception as e:
    print(f"❌ {type(e).__name__}: {e}")
    sys.exit(1)
PY
  )
  reply_text "$to" "= $out"
}

register_command "/calc" plugin_calc "安全计算：/calc <表达式>"
register_command "/算" plugin_calc "安全计算：/算 <表达式>"
