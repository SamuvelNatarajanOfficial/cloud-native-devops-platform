variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane (e.g. \"1.31\"). Check AWS's supported-version list before upgrading - EKS deprecates old versions on a schedule."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.31\" (major.minor, no patch version - EKS manages patches itself)."
  }
}

variable "cluster_role_arn" {
  description = "IAM role ARN the EKS control plane assumes (from the iam module)."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN EKS managed node group instances assume (from the iam module)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs. Included in the cluster's vpc_config so Kubernetes-managed internet-facing load balancers can be placed here; worker nodes never launch in these subnets."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs. Worker nodes launch exclusively here."
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Whether the EKS API server endpoint is reachable from inside the VPC. Left on so nodes/pods can always reach the control plane even if public access is later locked down."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet (subject to public_access_cidrs). Needed for kubectl from a laptop without a bastion/VPN; disable once you set one up."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Defaults to 0.0.0.0/0 for a frictionless portfolio demo - restrict this to your own IP/CIDR for anything beyond that."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ami_type" {
  description = "AMI type for the managed node group. AL2023 is the current AWS-recommended EKS-optimized AMI family (Amazon Linux 2 reached EKS end-of-support)."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "capacity_type" {
  description = "Node group capacity type: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be either \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group. t3.medium is the practical minimum for EKS - smaller instances leave too little allocatable memory/CPU after kubelet/system reservations."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for each worker node."
  type        = number
  default     = 20
}

variable "desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3
}

variable "cluster_enabled_log_types" {
  description = <<-EOT
    EKS control-plane log types to ship to CloudWatch Logs. Defaults to a
    minimal set ("api", "audit") rather than all five (adds "authenticator",
    "controllerManager", "scheduler") to keep CloudWatch ingestion/storage
    cost down in a dev/portfolio environment - add the rest if you need
    deeper troubleshooting visibility.
  EOT
  type        = list(string)
  default     = ["api", "audit"]
}

variable "cluster_log_retention_days" {
  description = "CloudWatch Logs retention for EKS control-plane logs."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
