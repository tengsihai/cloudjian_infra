# INF-01 装配（P-01）

module "storage" {
  source = "./modules/storage"

  project = var.project
  region  = var.region
}
