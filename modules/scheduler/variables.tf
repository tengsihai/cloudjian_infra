variable "project" {
  type    = string
  default = "cloudjian"
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "scheduler_role_arn" {
  description = "cloudjian-scheduler-role ARN（仅 Invoke maintenance:live）"
  type        = string
}

variable "schedule_timezone" {
  description = "调度时区（东京）"
  type        = string
  default     = "Asia/Tokyo"
}

variable "flexible_window_minutes" {
  description = <<-EOT
    弹性窗口（分钟）。函数未就绪窗口（方案 12.2 / 任务拆解 8.4）内
    直调失败可读；弹性窗口避免整点错过。设 0 = OFF。
  EOT
  type        = number
  default     = 60
}
