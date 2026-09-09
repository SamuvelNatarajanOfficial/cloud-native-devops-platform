output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (where worker nodes run)."
  value       = module.vpc.private_subnet_ids
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "ID of the EKS-managed cluster security group."
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster (for IRSA roles in later phases)."
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_arn" {
  description = "ARN of the EKS managed node group."
  value       = module.eks.node_group_arn
}

output "node_group_status" {
  description = "Status of the EKS managed node group."
  value       = module.eks.node_group_status
}

output "configure_kubectl" {
  description = "Command to update your local kubeconfig to point at this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider registered for this cluster (for any future IRSA role beyond the one this phase already wires up)."
  value       = module.eks.oidc_provider_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller - set this as networking/aws-load-balancer-controller's values-dev.yaml serviceAccount.annotations[\"eks.amazonaws.com/role-arn\"]."
  value       = module.aws_load_balancer_controller_irsa.role_arn
}

output "dns_certificate_arn" {
  description = "ACM certificate ARN from the dns module, if enable_dns = true - set this as helm/taskflow's apiGateway.ingress.certificateArn. Empty when enable_dns = false (the default)."
  value       = var.enable_dns ? module.dns[0].certificate_arn : ""
}

output "dns_zone_id" {
  description = "Route 53 hosted zone ID from the dns module, if enable_dns = true. Empty when enable_dns = false (the default)."
  value       = var.enable_dns ? module.dns[0].zone_id : ""
}
