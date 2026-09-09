variable "domain_name" {
  description = "The domain the ACM certificate (and, if create_hosted_zone, the Route 53 zone) is for, e.g. \"api.taskflow.example.com\". This is a placeholder-safe variable, not a real registered domain owned by this project - see docs/networking-architecture.md."
  type        = string
}

variable "subject_alternative_names" {
  description = "Additional domain names the ACM certificate should also cover (e.g. a wildcard or an apex-domain alternative)."
  type        = list(string)
  default     = []
}

variable "create_hosted_zone" {
  description = "If true, create a new Route 53 public hosted zone for domain_name. If false (default), look up an EXISTING hosted zone by that name instead - the far more common real-world case (the domain's zone already exists, e.g. registered elsewhere or already delegated). Set true only if this project should own the zone outright."
  type        = bool
  default     = false
}

variable "create_alb_alias_record" {
  description = "If true, create a Route 53 alias A/AAAA record pointing domain_name at an existing ALB (via alb_dns_name/alb_zone_id below). Left false by default because the ALB doesn't exist until the AWS Load Balancer Controller has actually created it from a real Ingress - see docs/networking-architecture.md#dns--route-53 for the bootstrapping order this implies."
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  description = "The ALB's own DNS name (e.g. from `kubectl get ingress` once a real Ingress exists), used only when create_alb_alias_record is true."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "The ALB's hosted zone ID (an AWS-published per-region constant for ALBs, NOT this module's own Route 53 zone ID), used only when create_alb_alias_record is true."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to resources this module creates that support tagging."
  type        = map(string)
  default     = {}
}
