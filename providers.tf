provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "cloudjian"
      ManagedBy   = "terraform"
      Repository  = "cloudjian_infra"
      Environment = "release"
    }
  }
}
