# HTTP API（API / Stage / JWT 授权器 / CORS）
# 路由与集成归 backend 部署时注册（契约 §2.6）；infra 不建 route/integration、不枚举函数名。
# 路由硬性约束（无 $default、N8 单独 NONE、maintenance 不暴露）由 backend CI 校验。

# ————————————————————————————— API + Stage —————————————————————————————

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project}-http-api"
  protocol_type = "HTTP"
  description   = "CloudJian business API; no $default route"

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
      method           = "$context.httpMethod"
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
# authorizationScopes 暂不声明：SRP 登录实际携带的 scope 待实测后补

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

# ————————————————————————————— 路由与集成（归 backend） —————————————————————————————
# backend 部署脚本按契约 §2 注册 integration + route + add-permission；
# infra 只建 API / Stage / JWT 授权器 / CORS 壳，不枚举函数、不建路由。
# 因此新增接口不需要改 infra；网关也不存在 $default 路由（硬性约束 1）。

# ————————————————————————————— 调用授权（函数侧由 backend add-permission） —————————————————————————————
# SourceArn 到 arn:aws:execute-api:...:<api-id>/* —— 归 backend。
# 这里只保证 api-id 可被 SSM 消费。
