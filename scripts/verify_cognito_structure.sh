#!/usr/bin/env bash
# P-04 结构门禁：密码策略、Token 有效期、SRP-only、WriteAttributes 空。
# Cognito 无 MaximumLength（TODO-PWD-01）——本脚本同时断言 TF 里没有 max_length 幻觉字段。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/cognito/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

grep -q 'minimum_length    = 8\|minimum_length = 8' "$TF" \
  && ok "MinimumLength=8" || err "密码最小长度不是 8"

grep -q 'require_symbols   = false\|require_symbols = false' "$TF" \
  && ok "RequireSymbols=false" || err "符号不应强制（P-B）"

for k in require_lowercase require_uppercase require_numbers; do
  grep -qE "$k\s*=\s*true" "$TF" && ok "$k=true" || err "$k 必须为 true"
done

# 不得出现 MaximumLength 幻觉（Cognito 无此参数）
if grep -qi 'maximum_length' "$TF"; then
  err "出现 maximum_length——Cognito 密码策略无此字段（TODO-PWD-01）"
else
  ok "无 maximum_length 幻觉字段"
fi

grep -qE 'access_token_validity\s*=\s*20' "$TF" \
  && ok "AccessToken=20h" || err "AccessToken 有效期不是 20"
grep -qE 'id_token_validity\s*=\s*20' "$TF" \
  && ok "IdToken=20h" || err "IdToken 有效期不是 20"

grep -q 'ALLOW_USER_SRP_AUTH' "$TF" \
  && ok "SRP 流已开" || err "缺少 ALLOW_USER_SRP_AUTH"
if grep -q 'ALLOW_REFRESH_TOKEN_AUTH\|ALLOW_USER_PASSWORD_AUTH\|ALLOW_CUSTOM_AUTH' "$TF"; then
  err "开了非 SRP 授权流（架构 4.2：无 RefreshToken、密码不出网）"
else
  ok "仅 SRP（无 refresh/password/custom 流）"
fi

grep -qE 'write_attributes\s*=\s*\[\]' "$TF" \
  && ok "WriteAttributes 空集" || err "WriteAttributes 应为空集"
grep -q 'enable_token_revocation\s*=\s*true' "$TF" \
  && ok "Revocation=true" || err "未开 EnableTokenRevocation"

grep -q 'generate_secret\s*=\s*false' "$TF" \
  && ok "公共客户端（无 secret）" || err "SPA 客户端不应带 secret"

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_cognito_structure: FAILED" >&2
  exit 1
fi
echo "verify_cognito_structure: PASSED"
