# 网关访问日志组（保留 30 天）

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "cloudjian-api-access"
  retention_in_days = 30
}
