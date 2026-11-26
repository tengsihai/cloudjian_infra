# tflint — 云笺 INF-10
# 只开与本仓相关的规则；避免全量默认规则误报托管服务新属性。

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS 插件体积大、CI 需网络装；本期用 terraform 核心规则 + 自定义断言脚本兜底
# （verify_static / verify_*_structure）。需要时再开：
# plugin "aws" { enabled = true version = "0.32.0" source = "github.com/terraform-linters/tflint-ruleset-aws" }

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = false # 根 variables 有描述；模块内大量默认值变量
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}
