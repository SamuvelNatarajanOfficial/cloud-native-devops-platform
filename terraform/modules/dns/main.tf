# --------------------------------------------------------------------------
# DNS + TLS certificate for TaskFlow's external endpoint. This module is
# NOT instantiated by default in terraform/environments/dev (see that
# environment's main.tf - it's wired in behind `enable_dns`, default
# false) because every resource below either requires a domain this
# project doesn't actually own, or an ALB that doesn't exist yet - see
# docs/networking-architecture.md#dns--route-53 for the full bootstrapping
# order. `terraform validate` succeeds regardless (no AWS API calls happen
# at validate time); `terraform plan`/`apply` against this module would
# require real AWS credentials AND a real domain, and were never run here.
# --------------------------------------------------------------------------

# The common case: the domain's hosted zone already exists (registered
# elsewhere, or managed by another part of the org) - look it up instead
# of assuming this project should own it.
data "aws_route53_zone" "existing" {
  count = var.create_hosted_zone ? 0 : 1
  name  = var.domain_name
}

# The less common case: this project should own the zone outright.
resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.domain_name
  tags  = var.tags
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}

# --------------------------------------------------------------------------
# ACM certificate, DNS-validated. This is what the ALB's HTTPS listener
# actually presents to clients - see
# docs/networking-architecture.md#tls--acm for why TLS terminates at the
# ALB rather than at the Ingress/pod.
# --------------------------------------------------------------------------
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# One CNAME record per domain ACM asks to validate (domain_name plus each
# of subject_alternative_names) - Kubernetes-native service discovery has
# no equivalent here; ACM validation is inherently a DNS-record exchange.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Blocks until ACM actually reports the certificate as issued - requires
# the validation records above to have genuinely propagated and been
# checked by ACM, which requires real AWS + real DNS. Never applied in
# this project (see this file's own header comment).
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# --------------------------------------------------------------------------
# The final "make the domain point at the ALB" step - deliberately
# optional and off by default: the ALB's DNS name is only known AFTER the
# AWS Load Balancer Controller has created it from a real Ingress (see
# helm/taskflow's apiGateway.ingress.enabled), which itself depends on
# this certificate already existing. Turn this on as a second `terraform
# apply` once alb_dns_name/alb_zone_id are known - see
# docs/networking-architecture.md#dns--route-53.
# --------------------------------------------------------------------------
resource "aws_route53_record" "alb_alias" {
  count   = var.create_alb_alias_record ? 1 : 0
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
