variable "region" {
  description = "AWS 区域（架构固定东京）"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "资源名前缀（命名规范：全小写 + 连字符）"
  type        = string
  default     = "cloudjian"
}

variable "enable_vpc" {
  description = <<-EOT
    是否部署 VPC 网络资源。方案 12.6 决策：**不建 VPC**，恒为 false。
    置 true 也不会部署任何网络资源——network 模块只保留空模块与接线说明，
    演进时需按 modules/network/README.md 补齐子网/NAT/S3 Endpoint 后再打开。
  EOT
  type        = bool
  default     = false
}

variable "budget_monthly_usd" {
  description = "AWS Budgets 月度阈值（USD），方案 12.7 固定 $5"
  type        = number
  default     = 5
}

variable "budget_alert_emails" {
  description = "预算告警收件人（80% / 100% 触发）；空列表则只建预算不订阅"
  type        = list(string)
  default     = []
}
