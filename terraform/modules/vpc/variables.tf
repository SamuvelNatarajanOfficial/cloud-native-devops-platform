variable "name_prefix" {
  description = "Prefix applied to the Name tag of every resource this module creates (e.g. \"taskflow-dev\")."
  type        = string
}

variable "cluster_name" {
  description = <<-EOT
    Name of the EKS cluster that will use this VPC. Only used for the
    `kubernetes.io/cluster/<name>` subnet tag EKS/the AWS Load Balancer
    Controller rely on to auto-discover subnets - this module does not
    create the cluster itself.
  EOT
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Public and private subnet ranges are carved out of this automatically."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across. One public + one private subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS requires worker nodes/control-plane ENIs to span at least 2 availability zones."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use a single, shared NAT gateway for all private subnets instead of
    one per AZ. Saves ~$32/month per additional AZ in a dev/portfolio
    environment at the cost of cross-AZ NAT resilience. Set to false for
    a production-grade, one-NAT-per-AZ topology.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
