output "zone_id" {
  description = "Route 53 hosted zone ID for domain_name (either the looked-up existing zone or the newly created one)."
  value       = local.zone_id
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate - set this as the Helm chart's apiGateway.ingress.certificateArn value (alb.ingress.kubernetes.io/certificate-arn annotation)."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "hosted_zone_name_servers" {
  description = "Name servers for the newly created zone (only set when create_hosted_zone is true) - delegate the domain to these at its registrar."
  value       = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : []
}
