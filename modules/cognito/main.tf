# Cognito 用户池与 App Client
# - App Client：Access/Id 各 20h、无 RefreshToken、WriteAttributes 空、Revocation
# - 密码策略：Cognito 只能管下限与字符类别；20 位上限由前端 + Lambda 校验（业务侧约束）
# - Groups：admin / user（role 真源在注册表，Group 只影响前端菜单）

resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-userpool-tokyo"

  # 自建登录页走 InitiateAuth(USER_SRP_AUTH)，不用 Hosted UI（命名规范 13.1）
  mfa_configuration = "OFF"

  auto_verified_attributes = [] # 邮箱/手机均不自动验证；开号由 admin-api 完成

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false # P-B：不强制符号
    # 注意：Cognito 无 MaximumLength 字段；20 位上限靠前端 + Lambda 前置校验
  }

  # 用户名作为登录标识：不设 username_attributes（仅接受 email/phone），
  # 用自定义 username schema（admin 开号时指定 username）
  username_configuration {
    case_sensitive = true
  }

  schema {
    name                = "username"
    attribute_data_type = "String"
    required            = true
    mutable             = false
    string_attribute_constraints {
      min_length = 3
      max_length = 64
    }
  }

  # 改密后 auth_time >= password_changed_at 由 Lambda 比对
  # 这里不开 advanced security（额外费用，成本预算内无此项目）
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.project}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false # 公共客户端（浏览器 SPA）
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  allowed_oauth_flows_user_pool_client = false

  # 只开 SRP：不给 RefreshToken 流，到期清 Token 跳登录
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
  ]

  # Token 有效期（小时）：Access/Id 各 20h；流程上无 RefreshToken
  access_token_validity  = 20
  id_token_validity      = 20
  refresh_token_validity = 1 # 字段必填但 flows 未开 refresh，客户端拿不到

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "hours"
  }

  # WriteAttributes 为空集：不允许客户端改写属性
  write_attributes = []

  # 回调：自建登录页，无 Hosted UI 回调
  callback_urls = []
  logout_urls   = []
}

# —— Groups（前端菜单用；权限真源仍是注册表 role） ——

resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "CloudJian administrators (menu only; role truth = _registry.parquet)"
  precedence   = 1
}

resource "aws_cognito_user_group" "user" {
  name         = "user"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "CloudJian default users"
  precedence   = 100
}
