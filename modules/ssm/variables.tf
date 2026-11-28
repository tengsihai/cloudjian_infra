variable "project" {
  type    = string
  default = "cloudjian"
}

variable "region" {
  description = "写入 /cloudjian/region 的值（同时作为参数值，非资源区域）"
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket" {
  description = "数据桶名 → /cloudjian/bucket"
  type        = string
}

variable "cdn_domain" {
  description = "CloudFront 域名 → /cloudjian/cdn-domain"
  type        = string
}

variable "cdn_arn" {
  description = "分发 ARN → /cloudjian/cdn-arn"
  type        = string
}

variable "api_url" {
  description = "HTTP API 基址（含 /dev）→ /cloudjian/api-url"
  type        = string
}

variable "user_pool_id" {
  description = "→ /cloudjian/user-pool-id"
  type        = string
}

variable "client_id" {
  description = "App Client ID → /cloudjian/client-id"
  type        = string
}

variable "lambda_exec_role_arn" {
  description = "→ /cloudjian/lambda-exec-role-arn"
  type        = string
}

variable "lambda_alias" {
  description = "→ /cloudjian/lambda-alias（契约固定 live）"
  type        = string
  default     = "live"
}

variable "api_id" {
  description = "→ /cloudjian/api-id（backend add-permission SourceArn）"
  type        = string
}

variable "jwt_authorizer_id" {
  description = "→ /cloudjian/jwt-authorizer-id（路由校验期望值）"
  type        = string
}

variable "maintenance_role_arn" {
  description = "→ /cloudjian/maintenance-role-arn（maintenance 函数专用执行角色）"
  type        = string
}
