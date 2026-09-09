output "role_arn" {
  description = "ARN of the IRSA role - set this as the eks.amazonaws.com/role-arn annotation on the trusted Kubernetes ServiceAccount."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role."
  value       = aws_iam_role.this.name
}
