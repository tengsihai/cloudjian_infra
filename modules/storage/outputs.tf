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

output "data_bucket_regional_domain_name" {
  description = "数据桶 regional domain（CloudFront S3 origin）"
  # provider 6.x 的 aws_s3_bucket 不再导出 regional_domain_name，按命名约定拼接
  value = "${aws_s3_bucket.data.id}.s3.${var.region}.amazonaws.com"
}
