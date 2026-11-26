variable "project" {
  type    = string
  default = "cloudjian"
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "data_bucket_arn" {
  description = "数据桶 ARN（storage 模块输出）"
  type        = string
}

variable "logs_bucket_arn" {
  description = "访问日志桶 ARN"
  type        = string
}

variable "cdn_distribution_arn" {
  description = "CloudFront 分发 ARN（invalidation 限定）"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "用户池 ARN（lambda Cognito 动作限定）"
  type        = string
}
