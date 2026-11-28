# IAM 装配（三仓 GHA 角色、Lambda 执行角色、Scheduler 角色）

module "iam" {
  source = "./modules/iam"

  project               = var.project
  region                = var.region
  data_bucket_arn       = module.storage.data_bucket_arn
  cdn_distribution_arn  = module.cdn.distribution_arn
  cognito_user_pool_arn = module.cognito.user_pool_arn
  api_id                = module.apigw.api_id
}
