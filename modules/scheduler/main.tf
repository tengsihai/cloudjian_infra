# EventBridge Scheduler
# 只建调度；目标为可推导 ARN 字符串，不校验函数存在、不建函数（硬性约束 5）。
# maintenance 不挂 API GW，仅 IAM 直调。

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # 别名固定 live；函数名固定 cloudjian-maintenance-api
  maintenance_alias_arn = "arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:cloudjian-maintenance-api:live"

  # 三类调度：task 名由 backend maintenance 解释
  schedules = {
    cloudjian-daily-reconcile = {
      expr = "cron(0 1 * * ? *)" # 每日 01:00 JST 收件箱对账
      task = "daily_reconcile"
      desc = "收件箱对账：按 grantee 重建 _share_inbox"
    }
    cloudjian-weekly-contract = {
      expr = "cron(0 4 ? * MON *)" # 每周一 04:00 JST 契约校验
      task = "weekly_contract"
      desc = "函数版本/别名/Layer ARN 契约校验"
    }
    cloudjian-daily-index-check = {
      expr = "cron(0 3 * * ? *)" # 每日 03:00 JST 索引抽查（只读）
      task = "daily_index_check"
      desc = "索引完整性抽查，只读"
    }
  }
}

# 调度组名必须匹配 IAM SourceArn 的 cloudjian-*（IAM 策略已收窄到该前缀）
resource "aws_scheduler_schedule_group" "main" {
  name = "${var.project}-schedules"

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "scheduler"
  }
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.schedules

  name       = each.key
  group_name = aws_scheduler_schedule_group.main.name

  schedule_expression          = each.value.expr
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = var.flexible_window_minutes > 0 ? "FLEXIBLE" : "OFF"
    # OFF 时忽略；FLEXIBLE 时生效
    maximum_window_in_minutes = var.flexible_window_minutes > 0 ? var.flexible_window_minutes : null
  }

  description = each.value.desc

  target {
    arn      = local.maintenance_alias_arn
    role_arn = var.scheduler_role_arn

    # task 由 maintenance 按 type 分发；不塞业务数据
    input = jsonencode({
      # maintenance 只认 aws.events（45-维护任务 §2 入参校验），其它取值直接拒绝执行
      source   = "aws.events"
      task     = each.value.task
      schedule = each.key
    })

    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
  # provider 6.x：aws_scheduler_schedule 无 tags 参数；标签在 group 上
}
