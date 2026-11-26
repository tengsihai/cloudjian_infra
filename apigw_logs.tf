# INF-05 访问日志组（架构 10.7：30 天保留）

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "cloudjian-api-access"
  retention_in_days = 30
}
