output "user_api_base_url" {
  description = "Base URL for the User API"
  value       = "${aws_apigatewayv2_api.user_api.api_endpoint}/${aws_apigatewayv2_stage.default.name}"
}
