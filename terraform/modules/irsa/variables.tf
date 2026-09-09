variable "role_name" {
  description = "Name for the IAM role this module creates."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider registered for the EKS cluster (the eks module's oidc_provider_arn output). This is the Federated principal the trust policy below allows to assume the role."
  type        = string
}

variable "oidc_issuer_url" {
  description = "The EKS cluster's OIDC issuer URL, WITH the \"https://\" scheme (the eks module's cluster_oidc_issuer_url output) - used to build the OIDC provider's condition keys, which AWS expects without the scheme prefix."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the ServiceAccount this role trusts (e.g. \"kube-system\")."
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes ServiceAccount this role trusts. The trust policy restricts assumption to exactly `system:serviceaccount:<namespace>:<service_account_name>` - no other ServiceAccount, in this cluster or any other trusting the same OIDC provider, can assume this role."
  type        = string
}

variable "policy_json" {
  description = "IAM policy document (JSON string) to attach to the role as an inline policy. Pass an already-validated JSON document (e.g. via `file(\"...\")`) rather than constructing it with string interpolation, so a syntax error is caught by `terraform validate`."
  type        = string
}

variable "tags" {
  description = "Tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
