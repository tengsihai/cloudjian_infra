output "log_group_names" {
  description = "6 个函数日志组（cloudjian-<fn>-api，30 天）"
  value       = sort(values(local.log_groups))
}

output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "budget_name" {
  value = aws_budgets_budget.monthly.name
}

output "budget_limit_usd" {
  value = var.budget_monthly_usd
}

output "cost_allocation_tag_keys" {
  value = ["Project", "Component", "Environment", "ManagedBy"]
}

output "alarm_names" {
  description = "交接 T4 的告警基线清单"
  value = sort([
    aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.cdn_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.conflict_412.alarm_name,
    aws_cloudwatch_metric_alarm.job_running.alarm_name,
    aws_cloudwatch_metric_alarm.share_revoked.alarm_name,
    aws_cloudwatch_metric_alarm.publish_failed.alarm_name,
  ])
}
