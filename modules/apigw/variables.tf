variable "project" {
  type    = string
  default = "cloudjian"
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "cdn_domain" {
  description = "CORS AllowOrigins（CDN 域名，派生不写死）"
  type        = string
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_client_id" {
  description = "JWT 授权器 Audience"
  type        = string
}
