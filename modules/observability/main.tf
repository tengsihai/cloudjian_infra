# INF-09 可观测与预算（架构 10.7 / 方案 12.7）
# - 38 个函数各一个日志组，组名与函数同名，保留 30 天（交付说明 8.5 归 INF-09）
# - 告警：Lambda 错误率、API 5xx、CF 5xx、412 冲突、发布失败、Budgets
# - JOB_RUNNING / SHARE_REVOKED 独立计数，不进 5xx 口径
# - Budgets $5/月 80%/100%；Cost Allocation Tags 四键激活

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # 架构 10.7：一个函数一个日志组，组名 = 函数名
  # 函数名已是 cloudjian-<域>-<动作>-api，不再拼 -api 后缀
  log_groups = { for fn in var.lambda_function_names : fn => fn }

  alarm_emails = var.budget_alert_emails
}

# ————————————————————————————— 日志组 —————————————————————————————

resource "aws_cloudwatch_log_group" "lambda_api" {
  for_each = local.log_groups

  name              = each.value
  retention_in_days = 30 # 架构 10.7 / 方案 12.7

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
    Function  = each.key
  }
}

# ————————————————————————————— 告警动作（SNS） —————————————————————————————

resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

resource "aws_sns_topic_subscription" "alarms_email" {
  for_each  = toset(local.alarm_emails)
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# ————————————————————————————— 5xx / 错误率 —————————————————————————————

# Lambda Errors（每函数）；函数未就绪 → notBreaching（8.4 首发布后转绿）
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(var.lambda_function_names)

  alarm_name          = "${each.key}-errors"
  alarm_description   = "Lambda Errors > 5 / 5min（${each.key}）；未部署期间 notBreaching"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions             = [aws_sns_topic.alarms.arn]
  ok_actions                = length(local.alarm_emails) > 0 ? [aws_sns_topic.alarms.arn] : []
  insufficient_data_actions = []

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

# API 5xx（HTTP API Stage）
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.project}-api-5xx"
  alarm_description   = "HTTP API 5xx（dev stage）；401/403/409/412 不在此口径"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = var.api_id, Stage = var.api_stage }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

# CloudFront 5xx 错误率
resource "aws_cloudwatch_metric_alarm" "cdn_5xx" {
  alarm_name          = "${var.project}-cdn-5xx"
  alarm_description   = "CloudFront 5xxErrorRate > 5% / 5min"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  dimensions          = { DistributionId = var.cdn_distribution_id, Region = "Global" }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 5
  unit                = "Percent"
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

# ————————————————————————————— 412 冲突（独立于 5xx） —————————————————————————————

resource "aws_cloudwatch_log_metric_filter" "conflict_412" {
  name           = "${var.project}-note-conflict-412"
  log_group_name = var.api_access_log_group_name
  # 访问日志为 JSON（apigw_logs format）：只数 412，不进 5xx 告警
  pattern = "{ $.status = 412 }"

  metric_transformation {
    name          = "NoteConflict412"
    namespace     = var.project
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "conflict_412" {
  alarm_name          = "${var.project}-conflict-412"
  alarm_description   = "If-Match 冲突 412 异常升高（乐观锁打爆）；独立于 5xx"
  namespace           = var.project
  metric_name         = "NoteConflict412"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 30
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

# ————————————————————————————— JOB_RUNNING / SHARE_REVOKED（不进 5xx） —————————————————————————————

# 业务侧单行 JSON 打点；infra 只建过滤器 + 计数告警（任务卡死/权限抖动）
resource "aws_cloudwatch_log_metric_filter" "job_running" {
  for_each = toset([
    "cloudjian-trash-purge-api",
    "cloudjian-notes-visibility-api",
    "cloudjian-dirs-move-api",
    "cloudjian-dirs-delete-api",
    "cloudjian-dirs-restore-api",
    "cloudjian-exports-create-api",
  ])

  name           = "${var.project}-${each.key}-job-running"
  log_group_name = each.key
  pattern        = "JOB_RUNNING"

  metric_transformation {
    name          = "JobRunning"
    namespace     = var.project
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "job_running" {
  alarm_name          = "${var.project}-job-running"
  alarm_description   = "JOB_RUNNING 打点升高（任务卡死）；独立计数，不计入 5xx"
  namespace           = var.project
  metric_name         = "JobRunning"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 2
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
    Metric    = "JOB_RUNNING"
  }
}

resource "aws_cloudwatch_log_metric_filter" "share_revoked" {
  name           = "${var.project}-share-revoked"
  log_group_name = "cloudjian-shares-revoke-api"
  pattern        = "SHARE_REVOKED"

  metric_transformation {
    name          = "ShareRevoked"
    namespace     = var.project
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "share_revoked" {
  alarm_name          = "${var.project}-share-revoked"
  alarm_description   = "SHARE_REVOKED 打点（权限抖动）；独立计数，不计入 5xx"
  namespace           = var.project
  metric_name         = "ShareRevoked"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 2
  threshold           = 40
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
    Metric    = "SHARE_REVOKED"
  }
}

# ————————————————————————————— 发布失败 —————————————————————————————
# backend CI 发布失败打点（namespace CloudJian / PublishFailed）；
# 函数未发布前 notBreaching，不轰炸（8.4）。

resource "aws_cloudwatch_metric_alarm" "publish_failed" {
  alarm_name          = "${var.project}-publish-failed"
  alarm_description   = "backend 发布失败打点（PublishFailed>0）；依赖 T3 CI 打点"
  namespace           = var.project
  metric_name         = "PublishFailed"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "observability"
  }
}

# ————————————————————————————— Budgets —————————————————————————————

resource "aws_budgets_budget" "monthly" {
  name              = var.project
  budget_type       = "COST"
  limit_amount      = tostring(var.budget_monthly_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-01-01_00:00"

  # 有邮箱才挂通知；空列表 = 只建预算（变量注释约定）
  dynamic "notification" {
    for_each = length(local.alarm_emails) > 0 ? [80, 100] : []
    content {
      notification_type          = "ACTUAL"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      comparison_operator        = "GREATER_THAN"
      subscriber_email_addresses = local.alarm_emails
    }
  }

  tags = {
    ManagedBy   = "terraform"
    Project     = var.project
    Component   = "observability"
    Environment = "dev"
  }
}

# ————————————————————————————— Cost Allocation Tags —————————————————————————————
# 方案 12.7：不激活则账单无法按项目归集

resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "component" {
  tag_key = "Component"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "environment" {
  tag_key = "Environment"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "managed_by" {
  tag_key = "ManagedBy"
  status  = "Active"
}
