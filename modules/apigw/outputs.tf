output "api_id" {
  description = "SSM /cloudjian/api-id"
  value       = aws_apigatewayv2_api.http.id
}

output "api_endpoint" {
  description = "SSM /cloudjian/api-url（含 stage dev）"
  # api_endpoint 本身不带 stage；业务基址必须含 /dev（架构 5.0）
  value = "${aws_apigatewayv2_api.http.api_endpoint}/${aws_apigatewayv2_stage.dev.name}"
}

output "authorizer_id" {
  description = "SSM /cloudjian/jwt-authorizer-id；get-routes 门禁期望值"
  value       = aws_apigatewayv2_authorizer.jwt.id
}

output "stage_name" {
  value = aws_apigatewayv2_stage.dev.name
}
