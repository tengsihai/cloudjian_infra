output "user_pool_id" {
  description = "SSM /cloudjian/user-pool-id"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "lambda-role Cognito 动作资源限定用"
  value       = aws_cognito_user_pool.main.arn
}

output "client_id" {
  description = "SSM /cloudjian/client-id；JWT 授权器 Audience"
  value       = aws_cognito_user_pool_client.app.id
}
