# 空模块：不部署任何网络资源（enable_vpc=false）。
# 保留变量与校验，使「打开开关却没实现」在 validate 阶段就失败，
# 而不是静默产出半套 VPC。

variable "enable_vpc" {
  description = "恒为 false；true 时必须先按 README 补齐实现"
  type        = bool
  default     = false
}

variable "project" {
  type    = string
  default = "cloudjian"
}

# 校验：当前实现只接受 false。补齐 VPC 实现时删除此 check 并按 README 接线。
check "vpc_not_implemented" {
  assert {
    condition     = !var.enable_vpc
    error_message = "modules/network 尚未实现 VPC（当前决策为不建 VPC）。演进前先阅读 modules/network/README.md 并补齐子网/NAT/S3 Endpoint 实现。"
  }
}

# 预留输出位（不产出任何资源）：
# outputs 将在实现后提供 vpc_id / private_subnet_ids / nat_id 等。
