#!/usr/bin/env bash
# 结构校验：三角色 sub 精确匹配、terraform 角色无 lambda:*、
# PassRole 限定、lambda-role 不含 deploy/*、scheduler 仅 maintenance:live。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/iam/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 1) 三条 sub 必须是 environment 口径；sub 用 StringLike，但只允许两种锚定形式：
#    老仓库 repo:org/repo:environment:release；immutable subject repo:org@id/repo@id:...
python - "$TF" <<'PY' || FAIL=1
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
found = sorted(set(re.findall(r'"repo:[^"]*:environment:release"', src)))
allowed = sorted({
    '"repo:tengsihai/cloudjian-%s:environment:release"' % r for r in ("frontend", "backend", "infra")
} | {
    '"repo:tengsihai@*/cloudjian-%s@*:environment:release"' % r for r in ("frontend", "backend", "infra")
})
if found != allowed:
    print("FAIL: sub 形式不符（多出或缺失）:", [p for p in found if p not in allowed] or "缺失",
          file=sys.stderr)
    sys.exit(1)
if "pull_request" in src:
    print("FAIL: sub 出现了 pull_request 口径", file=sys.stderr)
    sys.exit(1)
print("  ok: 三条 sub 仅 environment 口径，含 immutable subject 两种形式")
PY

# 2) terraform 角色不得出现 lambda:* 动作
if awk '/aws_iam_role_policy" "gha_terraform"/,/^}/' "$TF" | grep -qE '"lambda:[A-Z]'; then
  err "terraform 角色策略含 lambda:* 动作"
else
  ok "terraform 角色无 lambda:*"
fi

# 3) lambda-role 不得含 deploy/*（只查 Resource 行，跳过注释）
if awk '/aws_iam_role_policy" "lambda_execution"/,/^}/' "$TF" \
  | grep -E '^\s*(Resource|"[^"]*deploy)' \
  | grep -v '^\s*#' \
  | grep -q 'deploy/'; then
  err "lambda-role 含 deploy/*（Y9 最小权限）"
else
  ok "lambda-role 无 deploy/*"
fi

# 4) lambda-role 无 s3:* / iam:*
if awk '/aws_iam_role_policy" "lambda_execution"/,/^}/' "$TF" | grep -qE '"(s3|iam):\*"'; then
  err "lambda-role 出现 s3:* 或 iam:*"
else
  ok "lambda-role 无 s3:*/iam:*"
fi

# 5) PassRole 只在 backend(限 lambda-role) 与 terraform(限 scheduler-role) 出现
if grep -q 'PassLambdaRole\|PassSchedulerRole' "$TF"; then
  ok "PassRole 有命名限定"
else
  err "缺少命名的 PassRole 限定"
fi
if awk '/aws_iam_role_policy" "gha_terraform"/,/^}/' "$TF" | grep -q 'lambda_execution'; then
  err "terraform 角色可 PassRole 给 lambda（应仅 scheduler）"
else
  ok "terraform PassRole 不含 lambda 执行角色"
fi

# 6) scheduler 仅 maintenance:live（policy 内为 ${local.maintenance_function}:${local.lambda_alias} 插值）
SCHED_BLOCK=$(awk '/aws_iam_role_policy" "scheduler"/,/^}/' "$TF")
if echo "$SCHED_BLOCK" | grep -q 'local.maintenance_function' \
  && echo "$SCHED_BLOCK" | grep -q 'local.lambda_alias'; then
  ok "scheduler 限 maintenance:live"
else
  err "scheduler InvokeFunction 未限 maintenance:live"
fi
if echo "$SCHED_BLOCK" | grep -qE 'function:\*|function:\$\{var'; then
  err "scheduler 资源过宽"
fi

# 7) frontend 只能写 release/frontend
if awk '/aws_iam_role_policy" "gha_frontend"/,/^}/' "$TF" | grep -q 'release/frontend'; then
  ok "frontend 写方限 release/frontend"
else
  err "frontend PutParameter 未限 release/frontend"
fi

# 8) backend 写方限 release/* 与 lambda-*
if awk '/aws_iam_role_policy" "gha_backend"/,/^}/' "$TF" | grep -q 'release/\*'; then
  ok "backend 写方含 release/*"
else
  err "backend 写方缺少 release/*"
fi

# 9) lambda-role Cognito 段：动作逐一列举、限本池、含删除用户与自助改密所需动作
LAMBDA_BLOCK=$(awk '/aws_iam_role_policy" "lambda_execution"/,/^}/' "$TF")
if echo "$LAMBDA_BLOCK" | grep -q '"cognito-idp:\*"'; then
  err "lambda-role 使用 cognito-idp:*（必须逐一列举）"
else
  ok "Cognito 未使用通配动作"
fi
for act in GetUser AdminGetUser AdminUserGlobalSignOut AdminCreateUser AdminAddUserToGroup \
           AdminRemoveUserFromGroup AdminDisableUser AdminEnableUser AdminResetPassword AdminDeleteUser \
           ChangePassword; do
  if ! echo "$LAMBDA_BLOCK" | grep -q "\"cognito-idp:$act\""; then
    err "Cognito 动作缺 cognito-idp:$act"
  fi
done
if echo "$LAMBDA_BLOCK" | grep -q 'cognito_user_pool_arn'; then
  ok "Cognito 动作限本用户池"
else
  err "Cognito 动作 Resource 未收窄到用户池 ARN"
fi

# 10) 导出包在桶根 exports/：lambda-role 必须能写该前缀
if echo "$LAMBDA_BLOCK" | grep -q 'exports/\*'; then
  ok "lambda-role 覆盖桶根 exports/*"
else
  err "lambda-role 缺少 exports/*（导出包放桶根，不在用户目录）"
fi

# 11) 异步任务自调用：只放 :live 别名
if echo "$LAMBDA_BLOCK" | grep -q 'LambdaSelfInvoke'; then
  SELF=$(awk '/LambdaSelfInvoke/,/^      },/' "$TF")
  if echo "$SELF" | grep -q 'lambda_alias'; then
    ok "自调用 Resource 限到别名"
  else
    err "自调用 Resource 未限到别名（应引用 lambda_alias）"
  fi
  if echo "$SELF" | grep -qi 'LATEST'; then
    err "自调用包含 LATEST（只应放 :live 别名）"
  fi
else
  err "缺少 LambdaSelfInvoke（异步任务靠自调用续跑）"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_iam_structure: FAILED" >&2
  exit 1
fi
echo "verify_iam_structure: PASSED"
