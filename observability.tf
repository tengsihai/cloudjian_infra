# 可观测装配 — 告警、Budgets、成本标签

module "observability" {
  source = "./modules/observability"

  project                   = var.project
  api_id                    = module.apigw.api_id
  api_stage                 = module.apigw.stage_name
  api_access_log_group_name = aws_cloudwatch_log_group.api_access.name
  cdn_distribution_id       = module.cdn.distribution_id
  budget_monthly_usd        = var.budget_monthly_usd
  budget_alert_emails       = var.budget_alert_emails
}
