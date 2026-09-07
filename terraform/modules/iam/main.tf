# --------------------------------------------------------------------------
# This module intentionally creates only two IAM roles, each assumable by a
# single AWS service principal, with the minimum set of AWS-managed policies
# EKS documents as required. It never creates an IAM user or access key -
# every credential used against AWS here is a short-lived role assumption,
# not a long-lived secret.
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# EKS cluster (control plane) role
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
  tags               = var.tags
}

# Minimum AWS-managed policy required for the EKS control plane to manage
# cluster-owned resources (ENIs, security groups, etc.) on our behalf.
resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --------------------------------------------------------------------------
# EKS managed node group (worker node) role
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
  tags               = var.tags
}

# The three managed policies below are AWS's documented minimum for an EKS
# managed node group: node-to-control-plane communication, the VPC CNI's
# permission to attach ENIs/secondary IPs to nodes for pod networking, and
# read-only ECR pulls for node/pod images. No inline or wildcard ("*")
# permissions are granted anywhere in this module.
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
