//---------------------CI procedure-----------------------

data "aws_security_groups" "cb_sg" {
  filter {
    name = "group-name"
    values = [
      "default"]
  }
  filter {
    name = "vpc-id"
    values = [
      aws_vpc.stage_qa.id]
  }
}

resource "aws_iam_role" "cb_iam_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cb_iam_role" {
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ssm:DescribeParameters"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:us-west-2:639716861848:parameter/*",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:GetLifecyclePolicy",
        "ecr:GetLifecyclePolicyPreview",
        "ecr:ListTagsForResource",
        "ecr:DescribeImageScanFindings",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterfacePermission"
      ],
      "Resource": [
        "arn:aws:ec2:us-west-2:639716861848:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:Subnet": [
            "${aws_subnet.PrivateSubnetA.arn}",
            "${aws_subnet.PrivateSubnetB.arn}",
            "${aws_subnet.PrivateSubnetC.arn}"
          ],
          "ec2:AuthorizedService": "codebuild.amazonaws.com"
        }
      }
    },
    {
      "Sid": "S3AccessPolicy",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:GetObject",
        "s3:List*",
        "s3:PutObject"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
  role = aws_iam_role.cb_iam_role.id
}

resource "aws_s3_bucket" "spa_bucket" {
  bucket = "sp-app-bckt"
  acl = "private"
}

resource "aws_codebuild_project" "spa" {
  name = "spa"
  service_role = aws_iam_role.cb_iam_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image = "aws/codebuild/standard:2.0"
    type = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true
  }
  source {
    type = "CODEPIPELINE"
    location = "https://github.com/Silame83/simple-python-app.git"
    buildspec = <<EOF
version: 0.2

phases:
  install:
    runtime-versions:
      docker: 18
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
      - ECR_REPO_URI=192.168.68.101:5000/spa
      - echo $CODEBUILD_RESOLVED_SOURCE_VERSION
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - echo $COMMIT_HASH
      - git config --global user.name "Silame83"
      - git config --global user.email "silame83@gmail.com"
      - git config --global http.postBuffer 157286400
      - IMAGE_TAG=commitid-$COMMIT_HASH
      - echo $IMAGE_TAG
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $ECR_REPO_URI:$IMAGE_TAG .
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $ECR_REPO_URI:$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"api-container","imageUri":"%s"}]' $ECR_REPO_URI:$IMAGE_TAG > imagedefinitions.json
artifacts:
  files:
      - imagedefinitions.json
  discard-paths: yes
EOF
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = "log-group"
      stream_name = "log-stream"
    }
  }

  source_version = "master"

  vpc_config {
    security_group_ids = data.aws_security_groups.cb_sg.ids
    subnets = [
      aws_subnet.PrivateSubnetA.id,
      aws_subnet.PrivateSubnetB.id,
      aws_subnet.PrivateSubnetC.id
    ]
    vpc_id = aws_vpc.stage_qa.id
  }
  tags = {
    Environment = "QA"
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

resource "aws_codebuild_source_credential" "cb_sc" {
  auth_type = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token = "6ba2575cc829b0172c749f103d12626ff23c6738"
}

/*resource "aws_codebuild_webhook" "cb_webhook" {
  project_name = aws_codebuild_project.spa.name

  filter_group {
    filter {
      type = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type = "HEAD_REF"
      pattern = "master"
    }
  }
}*/

//----------------------------CD procedure--------------------------

resource "aws_iam_role" "cp_role" {
  name = "cp_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cp_policy" {
  name = "cp_policy"
  role = aws_iam_role.cp_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.spa_bucket.arn}",
        "${aws_s3_bucket.spa_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:AccessKubernetesApi",
        "ssm:GetParameter",
        "eks:ListUpdates",
        "eks:ListFargateProfiles"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_codepipeline" "cp" {
  name = "spa-deploy"
  role_arn = aws_iam_role.cp_role.arn
  artifact_store {
    location = aws_s3_bucket.spa_bucket.bucket
    type = "S3"
  }
  stage {
    name = "Source"

    action {
      category = "Source"
      name = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = "1"
      output_artifacts = [
        "source_output"]

      configuration = {
        Repo = "simple-python-app"
        Owner = "Silame83"
        Branch = "master"
        OAuthToken = "6ba2575cc829b0172c749f103d12626ff23c6738"
      }
    }
  }

  stage {
    name = "Build"

    action {
      category = "Build"
      name = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      input_artifacts = [
        "source_output"]
      output_artifacts = [
        "build_output"]
      version = "1"

      configuration = {
        ProjectName = "spa"
      }
    }
  }

//  stage {
//    name = "Deploy"
//
//    action {
//      category = "Deploy"
//      name = "Deploy"
//      owner = "AWS"
//      provider = "EKS"
//      input_artifacts = [
//        "build_output"]
//      version = "1"
//
//      configuration = {
//        ClusterName = "qa_cluster"
//        ServiceName = "spa-container"
//        //        ActionMode = "REPLACE_ON_FAILURE"
//        //        Capabilities = "CAPABILITY_AUTO_EXPAND,CAPABILITY_IAM"
//        //        OutputFileName = "imagedefinitions.json"
//        //        StackName = "QAStack"
//      }
//    }
//  }
  depends_on = [
    aws_codebuild_project.spa]
}

locals {
  webhook_secret = aws_codebuild_source_credential.cb_sc.token
}

resource "aws_codepipeline_webhook" "cp_webhook" {
  authentication = "GITHUB_HMAC"
  name = "cp_webhook"
  target_action = "Source"
  target_pipeline = aws_codepipeline.cp.name

  authentication_configuration {
    secret_token = local.webhook_secret
  }

  filter {
    json_path = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

/*resource "github_repository_webhook" "ghub_rw" {
  repository = "https://github.com/Silame83/simple-python-app"

  configuration {
    url = aws_codepipeline_webhook.cp_webhook.url
    content_type = "json"
    insecure_ssl = true
    secret = local.webhook_secret
  }

  events = [
    "push"]
}*/
