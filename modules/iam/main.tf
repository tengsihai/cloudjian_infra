# INF-06 IAM（架构 10.3 / 方案 12.5）
# 三仓 GHA 角色 + lambda 执行角色 + scheduler 角色。
# TODO-OPS-01：sub 必须以 assume-role-with-web-identity 回读实际值后定稿；
# 本模块默认写 environment 口径，immutable subject 形式见 variables.tf 说明。

# ————————————————————————————— 数据来源 —————————————————————————————

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # GHA OIDC 账号提供方（三仓共用一个 provider，角色用 sub 区分）
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # TODO-OPS-01：若仓库为 2026-07-15 后新建且启用 immutable subject claims，
  # sub 形如 repo:org@id/repo@id:environment:dev —— 以下三个变量改为实测值。
  # 实测方法见 scripts/verify_oidc_sub.sh。
  sub_frontend  = "repo:tengsihai/cloudjian-frontend:environment:dev"
  sub_backend   = "repo:tengsihai/cloudjian-backend:environment:dev"
  sub_terraform = "repo:tengsihai/cloudjian-infra:environment:dev"

  # 固定命名（架构 10.4 / 方案 12.3）
  lambda_function_names = [
    "cloudjian-notes-list-api",
    "cloudjian-notes-create-api",
    "cloudjian-notes-get-api",
    "cloudjian-notes-update-api",
    "cloudjian-notes-delete-api",
    "cloudjian-trash-purge-api",
    "cloudjian-versions-list-api",
    "cloudjian-versions-restore-api",
    "cloudjian-versions-get-api",
    "cloudjian-search-query-api",
    "cloudjian-dirs-list-api",
    "cloudjian-dirs-move-api",
    "cloudjian-dirs-create-api",
    "cloudjian-dirs-update-api",
    "cloudjian-dirs-delete-api",
    "cloudjian-dirs-restore-api",
    "cloudjian-jobs-get-api",
    "cloudjian-notes-visibility-api",
    "cloudjian-notes-public-get-api",
    "cloudjian-shares-list-api",
    "cloudjian-shares-create-api",
    "cloudjian-shares-revoke-api",
    "cloudjian-assets-presign-api",
    "cloudjian-assets-register-api",
    "cloudjian-assets-url-get-api",
    "cloudjian-assets-urls-api",
    "cloudjian-assets-list-api",
    "cloudjian-admin-users-list-api",
    "cloudjian-admin-users-create-api",
    "cloudjian-admin-users-update-api",
    "cloudjian-admin-users-reset-api",
    "cloudjian-admin-team-config-get-api",
    "cloudjian-admin-team-config-put-api",
    "cloudjian-profile-get-api",
    "cloudjian-profile-put-api",
    "cloudjian-exports-create-api",
    "cloudjian-exports-get-api",
    "cloudjian-maintenance-api",
  ]
  lambda_alias         = "live"
  maintenance_function = "cloudjian-maintenance-api"
}

# ————————————————————————————— OIDC 提供方 —————————————————————————————

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

# ————————————————————————————— 前端角色 —————————————————————————————

resource "aws_iam_role" "gha_frontend" {
  name = "${var.project}-gha-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.sub_frontend
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gha_frontend" {
  name = "${var.project}-gha-frontend"
  role = aws_iam_role.gha_frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WebPrefixOnly"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetObject"]
        Resource = [
          "${var.data_bucket_arn}",
          "${var.data_bucket_arn}/web/*",
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = ["web/", "web/*"]
          }
        }
      },
      {
        # ListBucket 无 prefix 条件时单独放行（AWS 要求 List 与对象动作分开）
        Sid      = "ListWeb"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.data_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["web/", "web/*"]
          }
        }
      },
      {
        Sid      = "CloudFrontInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = var.cdn_distribution_arn
      },
      {
        Sid      = "ReadParams"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian/*"
      },
      {
        # Y3：每 key 单一写方 —— frontend 只能写自己那条
        Sid      = "WriteOwnRelease"
        Effect   = "Allow"
        Action   = ["ssm:PutParameter"]
        Resource = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian/release/frontend"
      }
    ]
  })
}

# ————————————————————————————— 后端角色 —————————————————————————————

resource "aws_iam_role" "gha_backend" {
  name = "${var.project}-gha-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.sub_backend
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gha_backend" {
  name = "${var.project}-gha-backend"
  role = aws_iam_role.gha_backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # H4 冒烟「写后即删」+ 重试清残留必需（方案 12.5 K1）
        Sid    = "DeployArtifacts"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = [
          "${var.data_bucket_arn}/deploy/*",
        ]
      },
      {
        Sid      = "ListDeploy"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.data_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["deploy/", "deploy/*"]
          }
        }
      },
      {
        # Lambda 全套发布动作（方案 12.5；maintenance 也由本仓创建）
        Sid    = "LambdaPublish"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:GetAlias",
          "lambda:ListAliases",
          "lambda:ListVersionsByFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:UpdateAlias",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:PublishLayerVersion",
          "lambda:GetLayerVersion",
          "lambda:InvokeFunction",
          "lambda:ListFunctions",
          "lambda:TagResource",
          "lambda:UntagResource",
        ]
        Resource = [
          for n in local.lambda_function_names :
          "arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:${n}"
        ]
      },
      {
        Sid    = "LambdaLayer"
        Effect = "Allow"
        Action = [
          "lambda:PublishLayerVersion",
          "lambda:GetLayerVersion",
          "lambda:ListLayerVersions",
        ]
        Resource = "arn:${local.partition}:lambda:${var.region}:${local.account_id}:layer:cloudjian-*"
      },
      {
        # 精确到 lambda-role（方案 12.5）
        Sid      = "PassLambdaRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.lambda_execution.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      },
      {
        Sid      = "ReadParams"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian/*"
      },
      {
        # Y3：backend 只写 release/* 与 lambda-*，不得覆盖 infra 参数
        Sid    = "WriteOwnParams"
        Effect = "Allow"
        Action = ["ssm:PutParameter"]
        Resource = [
          "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian/release/*",
          "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian/lambda-*",
        ]
      }
    ]
  })
}

# ————————————————————————————— Terraform 角色 —————————————————————————————

resource "aws_iam_role" "gha_terraform" {
  name = "${var.project}-gha-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.sub_terraform
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "gha_terraform" {
  name = "${var.project}-gha-terraform"
  role = aws_iam_role.gha_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 显式列举 cloudjian-* 角色；不含 lambda:*（权限层保证 infra 不碰函数）
        Sid    = "ManageCloudjianRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider",
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
          "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-*",
          local.oidc_provider_arn,
        ]
      },
      {
        # PassRole 仅限调度角色（方案 12.5 F4）
        Sid      = "PassSchedulerRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.scheduler.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "scheduler.amazonaws.com"
          }
        }
      },
      {
        # 数据桶 + 状态桶 + 日志桶（ARN 显式列举）
        Sid    = "ManageBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:GetBucketLocation", "s3:GetBucketPolicy",
          "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:GetBucketVersioning",
          "s3:PutBucketVersioning", "s3:GetBucketEncryption", "s3:PutBucketEncryption",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketCORS", "s3:PutBucketCORS", "s3:DeleteBucketCORS",
          "s3:GetBucketLifecycleConfiguration", "s3:PutBucketLifecycleConfiguration",
          "s3:GetBucketLogging", "s3:PutBucketLogging", "s3:GetBucketOwnershipControls",
          "s3:PutBucketOwnershipControls", "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetLifecycleConfiguration", "s3:ListAllMyBuckets",
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
          "s3:GetObjectVersion", "s3:PutObjectAcl", "s3:GetObjectAcl",
          "s3:PutBucketAcl", "s3:GetBucketAcl",
        ]
        Resource = [
          var.data_bucket_arn,
          "${var.data_bucket_arn}/*",
          var.logs_bucket_arn,
          "${var.logs_bucket_arn}/*",
          "arn:${local.partition}:s3:::${var.project}-tfstate-tokyo",
          "arn:${local.partition}:s3:::${var.project}-tfstate-tokyo/*",
        ]
      },
      {
        Sid      = "ManageCDN"
        Effect   = "Allow"
        Action   = ["cloudfront:*"]
        Resource = "*"
      },
      {
        Sid    = "ManageCognito"
        Effect = "Allow"
        Action = ["cognito-idp:*"]
        Resource = [
          "arn:${local.partition}:cognito-idp:${var.region}:${local.account_id}:userpool/*",
        ]
      },
      {
        # 区域收窄（方案 12.6 取舍：api-id 含随机段无法按名收窄）
        Sid    = "ManageAPIGW"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = [
          "arn:${local.partition}:apigateway:${var.region}::/apis/*",
          "arn:${local.partition}:apigateway:${var.region}::/restapis/*",
        ]
      },
      {
        Sid    = "ManageLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:DescribeLogGroups", "logs:PutMetricFilter",
          "logs:DeleteMetricFilter", "logs:DescribeMetricFilters", "logs:PutSubscriptionFilter",
          "logs:DeleteSubscriptionFilter", "logs:TagResource", "logs:UntagResource",
          "logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogStreams",
        ]
        Resource = [
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/cloudjian-*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/cloudjian-*:*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:cloudjian-*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:cloudjian-*:*",
        ]
      },
      {
        # SSM：infra 是 /cloudjian/* 主写方（release/backend|frontend 除外，但 Put 放宽到
        # 整前缀以便 apply 写参数；三仓互不覆盖由各角色自己的 Put 限制造成）
        Sid    = "ManageParams"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath",
          "ssm:PutParameter", "ssm:DeleteParameter", "ssm:DescribeParameters",
          "ssm:LabelParameterVersion", "ssm:RemoveTagsFromResource", "ssm:AddTagsToResource",
        ]
        Resource = "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/cloudjian*"
      },
      {
        Sid      = "ManageBudgets"
        Effect   = "Allow"
        Action   = ["budgets:*"]
        Resource = "arn:${local.partition}:budgets:${var.region}:${local.account_id}:budget/${var.project}*"
      },
      {
        # 调度（方案 12.5：漏了会让 apply 建调度 AccessDenied）
        Sid    = "ManageScheduler"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule", "scheduler:GetSchedule", "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule", "scheduler:ListSchedules",
          "scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup", "scheduler:GetScheduleGroup",
          "scheduler:ListScheduleGroups", "scheduler:TagResource", "scheduler:UntagResource",
        ]
        Resource = [
          "arn:${local.partition}:scheduler:${var.region}:${local.account_id}:schedule-group/${var.project}-*",
          "arn:${local.partition}:scheduler:${var.region}:${local.account_id}:schedule/${var.project}-*",
        ]
      },
      {
        # 告警（架构 10.7）：PutMetricAlarm 等；资源按 cloudjian-* 前缀收窄
        Sid    = "ManageAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms",
          "cloudwatch:TagResource", "cloudwatch:UntagResource",
          "cloudwatch:PutMetricData",
        ]
        Resource = [
          "arn:${local.partition}:cloudwatch:${var.region}:${local.account_id}:alarm:cloudjian-*",
          "arn:${local.partition}:cloudwatch:${var.region}:${local.account_id}:*",
        ]
      },
      {
        # SNS 告警主题（80%/100% 邮件与告警动作）
        Sid    = "ManageAlarmTopics"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic", "sns:DeleteTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes",
          "sns:Subscribe", "sns:Unsubscribe", "sns:ListSubscriptionsByTopic", "sns:Publish",
          "sns:TagResource", "sns:UntagResource",
        ]
        Resource = [
          "arn:${local.partition}:sns:${var.region}:${local.account_id}:cloudjian-*",
        ]
      },
      {
        # Cost Allocation Tags 激活
        Sid      = "CostTags"
        Effect   = "Allow"
        Action   = ["ce:CreateCostAllocationTag", "ce:UpdateCostAllocationTagStatus", "ce:ListCostAllocationTags"]
        Resource = "*"
      },
      {
        # IAM 只读辅助（策略模拟）
        Sid      = "IAMReadOnly"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:SimulatePrincipalPolicy"]
        Resource = "*"
      }
    ]
  })
}

# ————————————————————————————— Lambda 执行角色 —————————————————————————————
# 归 infra 创建；backend 挂载不修改（架构 10.4 / 方案 12.3）

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.project}-lambda"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 限 users/*，不含 deploy/*（Y9 最小权限）
        Sid      = "S3UserData"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = "${var.data_bucket_arn}/users/*"
      },
      {
        Sid      = "S3ListUsers"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketTagging"]
        Resource = var.data_bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["users/", "users/*", ""]
          }
        }
      },
      {
        # 含 CreateLogGroup（AWSLambdaBasicExecutionRole 标准项）
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
          "logs:DescribeLogStreams", "logs:TagLogGroup",
        ]
        Resource = [
          # 默认路径 + 架构 10.7 自定义组（组名 = 函数名）
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/cloudjian-*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/cloudjian-*:*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:cloudjian-*",
          "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:cloudjian-*:*",
        ]
      },
      {
        # Cognito 9 动作，逐一列举限本池（方案 12.3）
        Sid    = "Cognito"
        Effect = "Allow"
        Action = [
          "cognito-idp:GetUser",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminUserGlobalSignOut",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminAddUserToGroup",
          "cognito-idp:AdminRemoveUserFromGroup",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
          "cognito-idp:AdminResetPassword",
        ]
        Resource = var.cognito_user_pool_arn
      },
      {
        # CloudFront 失效（visibility_migrate 公开→私有时清 CDN）
        # 由 lambda 执行；创建失效也允许（小规模）
        Sid      = "CFInvalidation"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = var.cdn_distribution_arn
      }
    ]
  })
}

# ————————————————————————————— Scheduler 角色 —————————————————————————————

resource "aws_iam_role" "scheduler" {
  name = "${var.project}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${local.partition}:scheduler:${var.region}:${local.account_id}:schedule-group/${var.project}-*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project}-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = "arn:${local.partition}:lambda:${var.region}:${local.account_id}:function:${local.maintenance_function}:${local.lambda_alias}"
    }]
  })
}
