# INF-05 HTTP API 路由与 JWT 授权器（架构 5.12 / 方案 12.1）
# 红线：无 $default；N8 单独 NONE；M4 DELETE /admin/users 不挂载；
#       maintenance 不暴露。路由键以共同接口契约 v0.1 §2 为准（§6 冻结确认前的基线）。

locals {
  # 固定命名推导集成 URI（方案 12.3：不 data引用函数，先建集成）
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region

  fn_arn = {
    notes  = "arn:aws:lambda:${local.region}:${local.account_id}:function:cloudjian-notes-api:live"
    share  = "arn:aws:lambda:${local.region}:${local.account_id}:function:cloudjian-share-api:live"
    asset  = "arn:aws:lambda:${local.region}:${local.account_id}:function:cloudjian-asset-api:live"
    admin  = "arn:aws:lambda:${local.region}:${local.account_id}:function:cloudjian-admin-api:live"
    export = "arn:aws:lambda:${local.region}:${local.account_id}:function:cloudjian-export-api:live"
    # maintenance 故意不在表内：不建集成、不暴露
  }

  # 8 组业务 + 派生路由（契约 §2）；target 为 fn_arn 键
  # auth=JWT → 挂授权器；auth=NONE → 仅 N8
  routes = [
    # 组1 notes 列表/新建
    { key = "GET /notes", fn = "notes", auth = "JWT" },
    { key = "POST /notes", fn = "notes", auth = "JWT" },
    # 组2 单篇 + purge
    { key = "GET /notes/{note_id}", fn = "notes", auth = "JWT" },
    { key = "PUT /notes/{note_id}", fn = "notes", auth = "JWT" },
    { key = "DELETE /notes/{note_id}", fn = "notes", auth = "JWT" },
    { key = "POST /trash/purge", fn = "notes", auth = "JWT" },
    # 组3 版本
    { key = "GET /notes/{note_id}/versions", fn = "notes", auth = "JWT" },
    { key = "POST /notes/{note_id}/versions/{ts}/restore", fn = "notes", auth = "JWT" },
    { key = "GET /notes/{note_id}/versions/{ts}", fn = "notes", auth = "JWT" },
    # 组4 搜索/目录/任务
    { key = "GET /search", fn = "notes", auth = "JWT" },
    { key = "GET /dirs", fn = "notes", auth = "JWT" },
    { key = "POST /dirs/move", fn = "notes", auth = "JWT" },
    { key = "POST /dirs", fn = "notes", auth = "JWT" },
    { key = "PATCH /dirs", fn = "notes", auth = "JWT" },
    { key = "DELETE /dirs", fn = "notes", auth = "JWT" },
    { key = "POST /dirs/restore", fn = "notes", auth = "JWT" },
    { key = "GET /jobs/{job_id}", fn = "notes", auth = "JWT" },
    # 组2 续：N7 可见性 + N8 公开读（NONE）
    { key = "POST /notes/{note_id}/visibility", fn = "notes", auth = "JWT" },
    { key = "GET /public/notes/{public_token}", fn = "notes", auth = "NONE" },
    # 组5 共享（H3 路径参数形态，TODO-API-06）
    { key = "GET /shares", fn = "share", auth = "JWT" },
    { key = "POST /shares", fn = "share", auth = "JWT" },
    { key = "DELETE /shares/{share_id}", fn = "share", auth = "JWT" },
    # 组6 图床
    { key = "POST /assets/presign", fn = "asset", auth = "JWT" },
    { key = "POST /assets/register", fn = "asset", auth = "JWT" },
    { key = "GET /assets/{asset_id}/url", fn = "asset", auth = "JWT" },
    { key = "POST /assets/urls", fn = "asset", auth = "JWT" },
    { key = "GET /assets", fn = "asset", auth = "JWT" },
    # 组7 管理（M4 不挂载）+ profile
    { key = "GET /admin/users", fn = "admin", auth = "JWT" },
    { key = "POST /admin/users", fn = "admin", auth = "JWT" },
    { key = "PATCH /admin/users/{sub}", fn = "admin", auth = "JWT" },
    { key = "POST /admin/users/{sub}/reset", fn = "admin", auth = "JWT" },
    { key = "GET /admin/team-config", fn = "admin", auth = "JWT" },
    { key = "PUT /admin/team-config", fn = "admin", auth = "JWT" },
    { key = "GET /profile", fn = "admin", auth = "JWT" },
    { key = "PUT /profile", fn = "admin", auth = "JWT" },
    # 组8 导出
    { key = "POST /exports", fn = "export", auth = "JWT" },
    { key = "GET /exports/{job_id}", fn = "export", auth = "JWT" },
  ]

  jwt_routes  = [for r in local.routes : r if r.auth == "JWT"]
  none_routes = [for r in local.routes : r if r.auth == "NONE"]
}

data "aws_caller_identity" "current" {}

# ————————————————————————————— API + Stage —————————————————————————————

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project}-http-api"
  protocol_type = "HTTP"
  description   = "CloudJian business API; no $default route (红线1)"

  cors_configuration {
    allow_origins     = ["https://${var.cdn_domain}"]
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers     = ["authorization", "content-type", "if-match"]
    expose_headers    = ["etag"]
    max_age           = 600
    allow_credentials = false
  }

  tags = {
    Component = "apigw"
  }
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "dev"
  auto_deploy = true

  default_route_settings {
    detailed_metrics_enabled = false
    throttling_burst_limit   = 100
    throttling_rate_limit    = 50
  }
}

# ————————————————————————————— JWT 授权器 —————————————————————————————
# Audience = App Client ID（AccessToken 无 aud，回退校验 client_id）
# TODO-AUTH-01：暂不声明 authorizationScopes，实测 SRP scope 后另 PR

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project}-jwt"

  jwt_configuration {
    audience = [var.cognito_client_id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# ————————————————————————————— 集成（指向别名 live，字符串 ARN） —————————————————————————————

resource "aws_apigatewayv2_integration" "fn" {
  for_each = local.fn_arn

  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value
  payload_format_version = "2.0"
  integration_method     = "POST"
  timeout_milliseconds   = 30000 # 网关 30s；函数 25s 留 5s
}

# ————————————————————————————— 路由 —————————————————————————————
# HTTP API 省略 authorization_type 默认 NONE（高危默认值）——全部显式声明。

resource "aws_apigatewayv2_route" "jwt" {
  for_each = { for r in local.jwt_routes : r.key => r }

  api_id    = aws_apigatewayv2_api.http.id
  route_key = each.value.key

  target             = "integrations/${aws_apigatewayv2_integration.fn[each.value.fn].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
  api_key_required   = false
}

# N8：唯一 NONE 业务路由（红线2）
resource "aws_apigatewayv2_route" "public_none" {
  for_each = { for r in local.none_routes : r.key => r }

  api_id             = aws_apigatewayv2_api.http.id
  route_key          = each.value.key
  target             = "integrations/${aws_apigatewayv2_integration.fn[each.value.fn].id}"
  authorization_type = "NONE"
  # 显式 NONE，不走默认
}

# 有意不建：$default 路由（红线1）、OPTIONS 路由（网关 CORS 自动应答）、
# DELETE /admin/users/{sub}（M4 不挂载）、maintenance 相关一切

# ————————————————————————————— 调用授权（函数侧由 backend add-permission） —————————————————————————————
# 架构 10.4：SourceArn 到 arn:aws:execute-api:...:<api-id>/* —— 归 backend。
# 这里只保证 api-id 可被 SSM 消费。
