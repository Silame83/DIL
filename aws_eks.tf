/*data "aws_ip_ranges" "eks-cl" {
  services = [
    "eks"]
  cidr_blocks = ["10.100.0.0/16"]
}*/
data "aws_iam_user" "username_ruslan" {
  user_name = "ruslan"
}

resource "aws_iam_user_ssh_key" "ruslan_ssh_key" {
  encoding = "SSH"
  public_key = file("~/.ssh/id_rsa.pub")
  username = data.aws_iam_user.username_ruslan.user_name
}

/*-------------------------Creating Cluster on EKS--------------------------*/

resource "aws_eks_cluster" "qa_cluster" {
  name = "qa_cluster"
  role_arn = aws_iam_role.qa_cluster_iam_role.arn
  vpc_config {
    //        cluster_security_group_id = "aws_security_group.EKSCluster.id"
/*    security_group_ids = [
      aws_security_group.EKSCluster.id]*/
    subnet_ids = [
      aws_subnet.PublicSubnetA.id,
      aws_subnet.PublicSubnetC.id
    ]
  }
  depends_on = [
    aws_vpc.stage_qa,
    aws_iam_role_policy_attachment.qa_cluster-AmazonEKSClusterPolicy
  ]
}

output "endpoint" {
  value = aws_eks_cluster.qa_cluster.endpoint
}

output "kubeconfig-certificate-authority-data" {
  value = aws_eks_cluster.qa_cluster.certificate_authority[0].data
}

resource "aws_iam_role" "qa_cluster_iam_role" {
  name = "eks-cluster-qa"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "qa_cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.qa_cluster_iam_role.name
}

/*---------------------------Creating Node group-----------------------------*/


/*data "tls_public_key" "pem_key" {
  private_key_pem = file("~/Documents/keys/qa.pem")
}*/

/*resource "aws_key_pair" "qa" {
  key_name = "qa"
  public_key = "key-07c9f153751ae647d"
}*/

resource "aws_eks_node_group" "qa_cluster_node" {
  cluster_name = aws_eks_cluster.qa_cluster.name
  node_group_name = "qa_cluster_node"
  node_role_arn = aws_iam_role.qa_cluster_iam_eks-node-group.arn
  subnet_ids = [
    aws_subnet.PublicSubnetB.id]
  instance_types = [
    "t3.xlarge"]

    remote_access {
      ec2_ssh_key = "qa"
/*      source_security_group_ids = [
        aws_security_group.EKSCluster.id]*/
    }

  scaling_config {
    desired_size = 2
    max_size = 4
    min_size = 2
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_iam_role_policy_attachment.qa_cluster-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.qa_cluster-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.qa_cluster-AmazonEC2ContainerRegistryReadOnly,
  ]
}
resource "aws_iam_role" "qa_cluster_iam_eks-node-group" {
  name = "eks-node-group-qa_cluster"

  assume_role_policy = jsonencode({
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "qa_cluster-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role = aws_iam_role.qa_cluster_iam_eks-node-group.name
}

resource "aws_iam_role_policy_attachment" "qa_cluster-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role = aws_iam_role.qa_cluster_iam_eks-node-group.name
}

resource "aws_iam_role_policy_attachment" "qa_cluster-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role = aws_iam_role.qa_cluster_iam_eks-node-group.name
}

/*module "eks" {
  source = "terraform-aws-modules/eks/aws"
  cluster_name = aws_eks_cluster.qa_cluster.name
  vpc_id = aws_vpc.stage_qa.id
  subnets = [
    "$(aws_subnet.PublicSubnetB)"]

  create_eks = false
}

data "aws_eks_cluster" "qa_cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "qa_cluster" {
  name = module.eks.cluster_id
}*/

/*
resource "aws_subnet" "eks_subnet" {
  count = 1

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block = cidrsubnet(aws_vpc.stage_qa.cidr_block, 8, count.index)
  vpc_id = aws_vpc.stage_qa.id

  tags = {
    "kubernetes.io/cluster/${aws_eks_cluster.qa_cluster.name}" = "shared"
  }
}*/

/*-----------------------------Kubernetes Cluster----------------------------------*/

/*
locals {

  tags = {
    Application = "QA-Colu"
    Contact = "Ruslan"
    Tool = "Terraform"
  }

  cluster_name = aws_eks_cluster.qa_cluster.name

  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${aws_eks_cluster.qa_cluster.certificate_authority.0.data}
    server: ${aws_eks_cluster.qa_cluster.endpoint}
  name: ${aws_eks_cluster.qa_cluster.name}
contexts:
- context:
    cluster: ${aws_eks_cluster.qa_cluster.name}
    namespace: kube-system
    user: ${aws_eks_cluster.qa_cluster.name}
  name: ${aws_eks_cluster.qa_cluster.name}
current-context: ${aws_eks_cluster.qa_cluster.name}
kind: Config
preferences: {}
users:
- name: ${aws_eks_cluster.qa_cluster.name}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      args:
      - token
      - -i
      - qa_cluster
      command: aws-iam-authenticator
      env: null
    KUBECONFIG
}
*/
