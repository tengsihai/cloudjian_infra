variable "project" {
  type    = string
  default = "cloudjian"
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "api_id" {
  description = "HTTP API ID（5xx 告警维度）"
  type        = string
}

variable "api_stage" {
  type    = string
  default = "dev"
}

variable "api_access_log_group_name" {
  description = "网关访问日志组（412 指标过滤源）"
  type        = string
}

variable "cdn_distribution_id" {
  description = "CloudFront 分发 ID（5xxErrorRate 维度）"
  type        = string
}

variable "budget_monthly_usd" {
  type    = number
  default = 5
}

variable "budget_alert_emails" {
  description = "80%/100% 预算邮件；空则预算无订阅（控制台可后补）"
  type        = list(string)
  default     = []
}

