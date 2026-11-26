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

variable "lambda_function_names" {
  description = "38 个固定函数名（37 个接口函数 + maintenance；日志组与 Errors 告警维度）"
  type        = list(string)
  default = [
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
    "cloudjian-maintenance-api",
  ]
}
