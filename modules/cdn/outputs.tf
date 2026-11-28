output "distribution_id" {
  description = "分发 ID（SSM 排障 / 失效 API）"
  value       = aws_cloudfront_distribution.cdn.id
}

output "distribution_arn" {
  description = "桶策略 AWS:SourceArn 用"
  value       = aws_cloudfront_distribution.cdn.arn
}

output "domain_name" {
  description = "CDN 域名（SSM /cloudjian/cdn-domain；CORS AllowOrigins）"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "oac_id" {
  value = aws_cloudfront_origin_access_control.data.id
}
