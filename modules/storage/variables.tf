variable "project" {
  description = "资源名前缀"
  type        = string
  default     = "cloudjian"
}

variable "region" {
  description = "AWS 区域（拼 S3 regional domain）"
  type        = string
  default     = "ap-northeast-1"
}
