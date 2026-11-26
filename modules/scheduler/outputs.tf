output "schedule_group_name" {
  value = aws_scheduler_schedule_group.main.name
}

output "schedule_names" {
  description = "三条调度名（结构门禁比对）"
  value       = sort([for k, _ in local.schedules : k])
}

output "schedule_arns" {
  value = { for k, s in aws_scheduler_schedule.this : k => s.arn }
}

output "target_arn" {
  description = "可推导 maintenance live ARN（不校验存在）"
  value       = local.maintenance_alias_arn
}
