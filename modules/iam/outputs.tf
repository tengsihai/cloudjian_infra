# 输出（供 SSM /cloudjian/lambda-exec-role-arn 等）

output "lambda_role_arn" {
  description = "cloudjian-lambda-role ARN（SSM /cloudjian/lambda-exec-role-arn；backend 挂载读取）"
  value       = aws_iam_role.lambda_execution.arn
}

output "scheduler_role_arn" {
  description = "cloudjian-scheduler-role ARN（调度目标角色）"
  value       = aws_iam_role.scheduler.arn
}

output "gha_frontend_role_arn" {
  value = aws_iam_role.gha_frontend.arn
}

output "gha_backend_role_arn" {
  value = aws_iam_role.gha_backend.arn
}

output "gha_terraform_role_arn" {
  value = aws_iam_role.gha_terraform.arn
}

output "maintenance_role_arn" {
  value = aws_iam_role.maintenance.arn
}
