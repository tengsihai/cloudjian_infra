# INF-02 OAC + INF-03 CloudFront 分发与 Function（架构 8.4 / 11.1）
# 三道闸之闸 1（桶策略）在 storage 模块，依赖本模块输出的 distribution_arn。

# ————————————————————————————— OAC —————————————————————————————

resource "aws_cloudfront_origin_access_control" "data" {
  name                              = "${var.project}-data-oac"
  description                       = "S3 data bucket via OAC; no public origin access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ————————————————————————————— Function（viewer-request 白名单） —————————————————————————————
# 闸 2：放行 /web/* 与 /users/{uuid}/assets/public/*；
# 其余 /users/*、index.parquet、.dir_meta.json、assets/private/* → 403 终态；
# 无扩展名 → rewrite /web/index.html（含 /p/{token}）；
# /web/* 交源站（缺失如实 404，不得改写成 HTML）。

resource "aws_cloudfront_function" "path_whitelist" {
  name    = "${var.project}-path-whitelist"
  runtime = "cloudfront-js-2.0"
  comment = "Path whitelist + SPA rewrite; private paths terminal 403 (架构 11.1 闸2)"
  publish = true
  code    = <<-EOT
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  function forbid() {
    return {
      status: "403",
      statusDescription: "Forbidden",
      headers: {
        "content-type": [{ key: "Content-Type", value: "text/plain" }]
      }
    };
  }

  // —— 闸 2a：敏感文件名一票 403（任意路径命中即拒） ——
  if (
    uri.indexOf("index.parquet") !== -1 ||
    uri.indexOf(".dir_meta.json") !== -1 ||
    uri.indexOf("/assets/private/") !== -1
  ) {
    return forbid();
  }

  // —— 闸 2b：/users/* 仅放行 assets/public 前缀 ——
  if (uri.indexOf("/users/") === 0) {
    // /users/{uuid}/assets/public/...
    var m = uri.match(/^\/users\/[^\/]+\/assets\/public(\/|$)/);
    if (!m) {
      return forbid();
    }
    return request; // 公开图交源站；缺失 404 如实返回
  }

  // —— /web/* 全放行（含缺失文件 → 源站 404，不 rewrite） ——
  if (uri.indexOf("/web/") === 0) {
    return request;
  }

  // —— 无扩展名（/、/login、/notes、/p/{token}…）→ SPA index ——
  var last = uri.substring(uri.lastIndexOf("/") + 1);
  if (last.indexOf(".") === -1) {
    request.uri = "/web/index.html";
    return request;
  }

  // —— 其余带扩展名路径：不在白名单 → 403 终态（无入口，非“堵”） ——
  return forbid();
}
EOT
}

# ————————————————————————————— 分发 —————————————————————————————

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project} web + public assets"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 东京 + 北美/欧洲，够用且低于全区域

  origin {
    origin_id                = "s3-data"
    origin_access_control_id = aws_cloudfront_origin_access_control.data.id
    domain_name              = var.data_bucket_regional_domain_name
  }

  # 默认 Behavior：* → S3（架构 8.4：必须存在，绕不过）
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-data"

    # CDN 静态资源用托管优化缓存；公开图单独 ordered 行为（见下）
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # 公开图：Origin 进入缓存键（架构 8.4 / 常见坑：首个无 Origin 响应
  # 会把“无 ACAO”缓存住 → canvas 缩略图间歇失败）
  ordered_cache_behavior {
    path_pattern     = "/users/*/assets/public/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-data"

    cache_policy_id = aws_cloudfront_cache_policy.origin_header.id

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  # SPA 用函数 rewrite，不用自定义错误页（403/404→200 与函数 403 互斥，架构 8.4）

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # 标准访问日志 → 数据桶同款日志桶（免费额度外只付存储；方案 12.7）
  logging_config {
    include_cookies = false
    bucket          = var.logs_bucket_domain_name
    prefix          = "cloudfront/"
  }

  tags = {
    Component = "cdn"
  }
}

# 托管缓存策略：CachingOptimized（/web 等静态资源）
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# 自定义：缓存键含 Origin 头（公开图 CORS 正确性优先于命中率）
resource "aws_cloudfront_cache_policy" "origin_header" {
  name        = "${var.project}-public-with-origin"
  comment     = "Cache key includes Origin so ACAO-cached responses cannot poison canvas"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Origin"]
      }
    }

    cookies_config {
      cookie_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}
