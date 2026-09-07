variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in resource naming/tagging."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Base name for the EKS cluster and related resources. The final cluster name is \"<cluster_name>-<environment>\"."
  type        = string
  default     = "taskflow"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane (major.minor only, e.g. \"1.31\")."
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets and worker nodes across. Must have at least 2 entries and belong to aws_region."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ (cost trade-off - see terraform/modules/vpc/variables.tf)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Node group capacity type: ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "desired_node_count" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_node_count >= 1
    error_message = "desired_node_count must be at least 1."
  }
}

variable "min_node_count" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.min_node_count >= 1
    error_message = "min_node_count must be at least 1."
  }
}

variable "max_node_count" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.max_node_count >= 1
    error_message = "max_node_count must be at least 1."
  }
}

variable "eks_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable from the public internet (subject to eks_public_access_cidrs)."
  type        = bool
  default     = true
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint. Restrict this to your own IP/CIDR (e.g. [\"203.0.113.4/32\"]) instead of leaving it open to the internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Extra tags merged into every resource's tags, on top of Project/Environment/ManagedBy."
  type        = map(string)
  default     = {}
}
