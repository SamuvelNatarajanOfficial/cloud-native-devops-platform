output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster (used to build a kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "ID of the security group EKS automatically creates and manages for the cluster (control plane <-> node communication)."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster, used to configure IRSA roles."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider registered for this cluster, for use in IRSA trust policies in later phases."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_arn" {
  description = "ARN of the managed node group."
  value       = aws_eks_node_group.default.arn
}

output "node_group_status" {
  description = "Status of the managed node group (e.g. ACTIVE, CREATING, DEGRADED)."
  value       = aws_eks_node_group.default.status
}

output "node_group_scaling_config" {
  description = "Effective desired/min/max size of the managed node group."
  value       = aws_eks_node_group.default.scaling_config
}
