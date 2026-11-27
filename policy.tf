# 桶策略与 CORS 装配（依赖 cdn 输出的分发 ARN/域名）
# 桶策略只允许两条 Resource；SourceArn 用分发 ARN，禁止写死账户 ID。

module "cdn" {
  source = "./modules/cdn"

  project                          = var.project
  data_bucket_regional_domain_name = module.storage.data_bucket_regional_domain_name
  logs_bucket_domain_name          = "${module.storage.logs_bucket_id}.s3.amazonaws.com"
}

# 二段式：storage 提供桶，cdn 提供分发；桶策略在根上组装以避免模块循环
resource "aws_s3_bucket_policy" "data_cloudfront" {
  bucket = module.storage.data_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontReadWeb"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = ["${module.storage.data_bucket_arn}/web/*"]
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cdn.distribution_arn
          }
        }
      },
      {
        Sid       = "AllowCloudFrontReadPublicAssets"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = ["${module.storage.data_bucket_arn}/users/*/assets/public/*"]
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = module.cdn.distribution_arn
          }
        }
      }
    ]
  })

  depends_on = [module.storage]
}

# CORS：直传/读图；ExposeHeaders 必须含 ETag（否则前端直传后登记必失败）
resource "aws_s3_bucket_cors_configuration" "data" {
  bucket = module.storage.data_bucket_id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = ["https://${module.cdn.domain_name}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
