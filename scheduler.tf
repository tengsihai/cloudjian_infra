# 调度装配 — EventBridge Scheduler

module "scheduler" {
  source = "./modules/scheduler"

  project            = var.project
  region             = var.region
  scheduler_role_arn = module.iam.scheduler_role_arn
}
