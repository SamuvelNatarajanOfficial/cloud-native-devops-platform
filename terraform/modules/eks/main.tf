# --------------------------------------------------------------------------
# EKS control plane
# --------------------------------------------------------------------------
# Created before the cluster so its log group already exists when the
# cluster starts shipping logs to it (and so retention is enforced from
# the very first log line instead of defaulting to "never expire").
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  # Control-plane ENIs span both subnet tiers so that Kubernetes-managed
  # load balancers can be provisioned into either the tagged public or
  # private subnets, depending on the Service/Ingress. Worker nodes
  # themselves (the node group below) are restricted to private subnets
  # only - see that resource for why.
  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # "API_AND_CONFIG_MAP" uses EKS's modern cluster access management
  # instead of requiring a manually-maintained aws-auth ConfigMap: it
  # automatically grants the IAM principal that creates the cluster (i.e.
  # whoever runs `terraform apply`) cluster-admin via a bootstrap access
  # entry, so `aws eks update-kubeconfig` + kubectl work immediately.
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.cluster]
}

# --------------------------------------------------------------------------
# IRSA (IAM Roles for Service Accounts) support
# --------------------------------------------------------------------------
# The OIDC provider lives in this module (rather than the iam module)
# because it depends on the cluster's own OIDC issuer URL, which only
# exists once the cluster does - putting it in iam/ would create a
# circular module dependency. No IRSA roles are created yet; this just
# makes the provider available so a later phase (GitOps/observability
# controllers such as the AWS Load Balancer Controller or Cluster
# Autoscaler) can grant pod-scoped AWS permissions instead of broadening
# the shared node IAM role.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# --------------------------------------------------------------------------
# Managed node group
# --------------------------------------------------------------------------
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = var.node_role_arn

  # Worker nodes only ever launch in private subnets: they need no
  # inbound path from the internet, and their outbound access (pulling
  # images, package updates) goes out through the NAT gateway instead of
  # a public IP on the instance itself.
  subnet_ids = var.private_subnet_ids

  ami_type       = var.ami_type
  capacity_type  = var.capacity_type
  instance_types = var.node_instance_types
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  # The node IAM role's policy attachments and the cluster itself must
  # exist before EKS can launch instances with this role into it.
  depends_on = [aws_eks_cluster.this]
}
