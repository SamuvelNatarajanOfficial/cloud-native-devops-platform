output "cluster_role_arn" {
  description = "ARN of the IAM role the EKS control plane assumes."
  value       = aws_iam_role.cluster.arn
}

output "cluster_role_name" {
  description = "Name of the IAM role the EKS control plane assumes."
  value       = aws_iam_role.cluster.name
}

output "node_role_arn" {
  description = "ARN of the IAM role EKS managed node group instances assume."
  value       = aws_iam_role.node.arn
}

output "node_role_name" {
  description = "Name of the IAM role EKS managed node group instances assume."
  value       = aws_iam_role.node.name
}
