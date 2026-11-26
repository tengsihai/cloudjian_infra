variable "project" {
  type    = string
  default = "cloudjian"
}

variable "data_bucket_regional_domain_name" {
  description = "数据桶 regional domain（S3 origin）"
  type        = string
}

variable "logs_bucket_domain_name" {
  description = "日志桶 s3 website/domain（CloudFront logging_config.bucket）"
  type        = string
}
