# 桶与生命周期
# - 数据桶：BPA、Versioning、加密、标签生命周期
# - 无日志桶（成本取舍：S3/CloudFront 访问日志均不落 S3，可观测走 CloudWatch）
# - 状态桶由 scripts/bootstrap_state.sh 创建（不进本状态，避免自举循环）
# - 生命周期一律 cj:retention 标签过滤，禁止 prefix（字面匹配命中 0 个不报错）

locals {
  name = var.project # cloudjian
}

# ————————————————————————————— 数据桶 —————————————————————————————

resource "aws_s3_bucket" "data" {
  bucket = "${local.name}-data-tokyo"
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ————————————————————————————— 生命周期（标签，不用前缀） —————————————————————————————
# prefix 是字面匹配：users/*/trash/ 命中 0 个且不报错，所以生命周期只用标签。
# 三条规则 = 两个标签档 + 一个桶级兜底。

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  # 档 1：回收站 / 版本历史 / 随删图片 —— 30 天
  # 写入侧由 backend 的 put_with_retention / copy_with_retention 打标
  rule {
    id     = "retention-30d"
    status = "Enabled"

    filter {
      tag {
        key   = "cj:retention"
        value = "30d"
      }
    }

    expiration {
      days = 30
    }

    # 30d 档对象若被高频覆盖，非当前版本同样按 7 天 / 留 3 份收敛
    noncurrent_version_expiration {
      noncurrent_days           = 7
      newer_noncurrent_versions = 3
    }
  }

  # 档 2：导出 ZIP、search/segments、public_index/segments —— 1 天（写入侧打标）
  rule {
    id     = "retention-1d"
    status = "Enabled"

    filter {
      tag {
        key   = "cj:retention"
        value = "1d"
      }
    }

    expiration {
      days = 1
    }
  }

  # 桶级兜底：无标签对象（正文、index.parquet、shards、_refs、jobs…）
  # 非当前版本 7 天 + 只留 3 份 + 删除标记过期 + 未完成分片 7 天
  # 注：expired_object_delete_marker 为布尔属性，与 expiration 块互斥（只清删除标记的规则不设 expiration）
  # 注：abort_incomplete_multipart_upload 不能出现在带 tag 过滤的规则里（S3 限制），
  #     所以只放在这条无过滤的规则中，对全桶生效。
  rule {
    id     = "bucket-fallback-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 7
      newer_noncurrent_versions = 3
    }

    # 只删过期删除标记：expiration 内布尔位，与 days/date 互斥
    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
