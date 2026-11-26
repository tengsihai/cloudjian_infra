#!/usr/bin/env bash
# P-03 Function 行为矩阵（架构 11.1 闸3 / 交付说明验收）。
# 匿名请求断言：放行 200、私有 403、SPA rewrite 200、缺失静态 404。
#
# 用法：
#   CF_DOMAIN=dxxx.cloudfront.net ./scripts/verify_cdn_matrix.sh
set -euo pipefail

CF_DOMAIN="${CF_DOMAIN:-${1:-}}"
if [[ -z "$CF_DOMAIN" ]]; then
  # 尝试从 SSM 读
  CF_DOMAIN=$(aws ssm get-parameter --name /cloudjian/cdn-domain \
    --query 'Parameter.Value' --output text 2>/dev/null || true)
fi
[[ -n "$CF_DOMAIN" ]] || { echo "CF_DOMAIN 未设置且 SSM 读取失败" >&2; exit 1; }

BASE="https://${CF_DOMAIN}"
FAIL=0
pass=0

# status期望  [path] [expect]
# 200/403/404
assert_status() {
  local path="$1" want="$2" label="$3"
  local got
  got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${BASE}${path}" || echo "000")
  if [[ "$got" == "$want" ]]; then
    echo "  ok  [$got] $label  ($path)"
    pass=$((pass+1))
  else
    echo "FAIL  [$got≠$want] $label  ($path)" >&2
    FAIL=1
  fi
}

echo "==> CDN behavior matrix against ${BASE}"

# SPA 路由 → 200 同一 index
for p in / /login /notes /admin /notes/abc /p/AbCdEfGhIjKlMnOpQrStUv; do
  assert_status "$p" 200 "SPA rewrite"
done

# /web 静态资源存在时 200（index.html 一定在）
assert_status "/web/index.html" 200 "static index"
# 缺失静态文件必须 404，不得被改写成 HTML
assert_status "/web/missing.js" 404 "missing static 404"

# 公开图：用一个不存在的对象 → 404（源站），但**不能**是 403（证明放行到源站）
# 真实 200 用例需造数：P-07 联调时补 assets/public 真图
assert_status "/users/00000000-0000-0000-0000-000000000000/assets/public/nope.png" 404 "public asset reaches origin"

# 私有/敏感路径 → 403 终态（闸 2 + 闸 3）
U="users/00000000-0000-0000-0000-000000000000"
assert_status "/${U}/notes/secret.md" 403 "private note path"
assert_status "/${U}/index.parquet" 403 "index.parquet"
assert_status "/${U}/.dir_meta.json" 403 "dir_meta"
assert_status "/${U}/assets/private/x.png" 403 "private asset"
assert_status "/${U}/assets/_refs.json" 403 "refs json"
assert_status "/${U}/search/shard-0.json.gz" 403 "search shard"

# 带扩展名但不在白名单 → 403
assert_status "/evil.png" 403 "unknown extension"

echo "==> ${pass} passed, FAIL=${FAIL}"
if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_cdn_matrix: FAILED" >&2
  exit 1
fi
echo "verify_cdn_matrix: PASSED"
