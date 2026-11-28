# 存储装配（数据桶、生命周期、桶策略依赖）

module "storage" {
  source = "./modules/storage"

  project = var.project
  region  = var.region
}
