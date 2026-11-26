# 状态后端：S3 状态桶与业务桶物理分离（架构 6.1）。
# 首次使用前先跑 scripts/bootstrap_state.sh 创建状态桶；
# 之后用 -backend-config 参数或下方注释打开（bucket/region/dynamodb 由 bootstrap 输出）。
terraform {
  backend "s3" {
    bucket       = "cloudjian-tfstate-tokyo"
    key          = "cloudjian-infra/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
