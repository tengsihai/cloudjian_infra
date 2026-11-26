output "data_bucket_id" {
  description = "数据桶名（SSM /cloudjian/bucket）"
  value       = aws_s3_bucket.data.id
}

output "data_bucket_arn" {
  value = aws_s3_bucket.data.arn
}

output "logs_bucket_id" {
  description = "S3 访问日志桶（保留 30 天）"
  value       = aws_s3_bucket.logs.id
}
