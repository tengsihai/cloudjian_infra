output "parameter_names" {
  description = "infra 管理的参数全名（结构校验比对用）"
  value = concat(
    sort([for k, _ in local.bus : "/${var.project}/${k}"]),
    ["/${var.project}/release/archive"],
  )
}

output "path" {
  description = "参数总线前缀"
  value       = "/${var.project}/"
}

output "api_url" {
  value = aws_ssm_parameter.bus["api-url"].value
}

output "cdn_domain" {
  value = aws_ssm_parameter.bus["cdn-domain"].value
}

output "jwt_authorizer_id" {
  value = aws_ssm_parameter.bus["jwt-authorizer-id"].value
}
