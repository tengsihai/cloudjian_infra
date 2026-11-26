# INF-05 HTTP API 路由与 JWT 授权器（架构 5.12 / 方案 12.1）
# 红线：无 $default；N8 单独 NONE；M4 DELETE /admin/users 不挂载；
#       maintenance 不暴露。路由键以共同接口契约 v0.1 §2 为准（§6 冻结确认前的基线）。

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.region

  # 固定命名推导集成 URI（方案 12.3：不 data 引用函数，先建集成）
  # 一路由一函数（契约 §2.6）：37 个业务函数，命名 cloudjian-<域>-<动作>-api
  function_names = [
    "cloudjian-notes-list-api",
    "cloudjian-notes-create-api",
    "cloudjian-notes-get-api",
    "cloudjian-notes-update-api",
    "cloudjian-notes-delete-api",
    "cloudjian-trash-purge-api",
    "cloudjian-versions-list-api",
    "cloudjian-versions-restore-api",
    "cloudjian-versions-get-api",
    "cloudjian-search-query-api",
    "cloudjian-dirs-list-api",
    "cloudjian-dirs-move-api",
    "cloudjian-dirs-create-api",
    "cloudjian-dirs-update-api",
    "cloudjian-dirs-delete-api",
    "cloudjian-dirs-restore-api",
    "cloudjian-jobs-get-api",
    "cloudjian-notes-visibility-api",
    "cloudjian-notes-public-get-api",
    "cloudjian-shares-list-api",
    "cloudjian-shares-create-api",
    "cloudjian-shares-revoke-api",
    "cloudjian-assets-presign-api",
    "cloudjian-assets-register-api",
    "cloudjian-assets-url-get-api",
    "cloudjian-assets-urls-api",
    "cloudjian-assets-list-api",
    "cloudjian-admin-users-list-api",
    "cloudjian-admin-users-create-api",
    "cloudjian-admin-users-update-api",
    "cloudjian-admin-users-reset-api",
    "cloudjian-admin-team-config-get-api",
    "cloudjian-admin-team-config-put-api",
    "cloudjian-profile-get-api",
    "cloudjian-profile-put-api",
    "cloudjian-exports-create-api",
    "cloudjian-exports-get-api",
  ]

  fn_arn = { for n in local.function_names :
    n => "arn:aws:lambda:${local.region}:${local.account_id}:function:${n}:live"
  }

  # 每条路由恰好接一个函数；auth=JWT → 挂授权器，auth=NONE → 仅 N8
  # maintenance 故意不在表内：不建集成、不暴露
  routes = [
    # 笔记
    { key = "GET /notes", fn = "cloudjian-notes-list-api", auth = "JWT" },
    { key = "POST /notes", fn = "cloudjian-notes-create-api", auth = "JWT" },
    { key = "GET /notes/{note_id}", fn = "cloudjian-notes-get-api", auth = "JWT" },
    { key = "PUT /notes/{note_id}", fn = "cloudjian-notes-update-api", auth = "JWT" },
    { key = "DELETE /notes/{note_id}", fn = "cloudjian-notes-delete-api", auth = "JWT" },
    # 回收站
    { key = "POST /trash/purge", fn = "cloudjian-trash-purge-api", auth = "JWT" },
    # 版本
    { key = "GET /notes/{note_id}/versions", fn = "cloudjian-versions-list-api", auth = "JWT" },
    { key = "POST /notes/{note_id}/versions/{ts}/restore", fn = "cloudjian-versions-restore-api", auth = "JWT" },
    { key = "GET /notes/{note_id}/versions/{ts}", fn = "cloudjian-versions-get-api", auth = "JWT" },
    # 搜索
    { key = "GET /search", fn = "cloudjian-search-query-api", auth = "JWT" },
    # 目录
    { key = "GET /dirs", fn = "cloudjian-dirs-list-api", auth = "JWT" },
    { key = "POST /dirs/move", fn = "cloudjian-dirs-move-api", auth = "JWT" },
    { key = "POST /dirs", fn = "cloudjian-dirs-create-api", auth = "JWT" },
    { key = "PATCH /dirs", fn = "cloudjian-dirs-update-api", auth = "JWT" },
    { key = "DELETE /dirs", fn = "cloudjian-dirs-delete-api", auth = "JWT" },
    { key = "POST /dirs/restore", fn = "cloudjian-dirs-restore-api", auth = "JWT" },
    # 任务
    { key = "GET /jobs/{job_id}", fn = "cloudjian-jobs-get-api", auth = "JWT" },
    # 笔记
    { key = "POST /notes/{note_id}/visibility", fn = "cloudjian-notes-visibility-api", auth = "JWT" },
    # 笔记·公开读
    { key = "GET /public/notes/{public_token}", fn = "cloudjian-notes-public-get-api", auth = "NONE" },
    # 共享
    { key = "GET /shares", fn = "cloudjian-shares-list-api", auth = "JWT" },
    { key = "POST /shares", fn = "cloudjian-shares-create-api", auth = "JWT" },
    { key = "DELETE /shares/{share_id}", fn = "cloudjian-shares-revoke-api", auth = "JWT" },
    # 图床
    { key = "POST /assets/presign", fn = "cloudjian-assets-presign-api", auth = "JWT" },
    { key = "POST /assets/register", fn = "cloudjian-assets-register-api", auth = "JWT" },
    { key = "GET /assets/{asset_id}/url", fn = "cloudjian-assets-url-get-api", auth = "JWT" },
    { key = "POST /assets/urls", fn = "cloudjian-assets-urls-api", auth = "JWT" },
    { key = "GET /assets", fn = "cloudjian-assets-list-api", auth = "JWT" },
    # 管理
    { key = "GET /admin/users", fn = "cloudjian-admin-users-list-api", auth = "JWT" },
    { key = "POST /admin/users", fn = "cloudjian-admin-users-create-api", auth = "JWT" },
    { key = "PATCH /admin/users/{sub}", fn = "cloudjian-admin-users-update-api", auth = "JWT" },
    { key = "POST /admin/users/{sub}/reset", fn = "cloudjian-admin-users-reset-api", auth = "JWT" },
    { key = "GET /admin/team-config", fn = "cloudjian-admin-team-config-get-api", auth = "JWT" },
    { key = "PUT /admin/team-config", fn = "cloudjian-admin-team-config-put-api", auth = "JWT" },
    # 个人设置
    { key = "GET /profile", fn = "cloudjian-profile-get-api", auth = "JWT" },
    { key = "PUT /profile", fn = "cloudjian-profile-put-api", auth = "JWT" },
    # 导出
    { key = "POST /exports", fn = "cloudjian-exports-create-api", auth = "JWT" },
    { key = "GET /exports/{job_id}", fn = "cloudjian-exports-get-api", auth = "JWT" },
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

  access_log_settings {
    destination_arn = var.access_log_group_arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

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
