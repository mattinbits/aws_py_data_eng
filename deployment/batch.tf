# ECR Repository for Batch container images
resource "aws_ecr_repository" "batch_satellite_brightness" {
  name                 = "batch-satellite-brightness"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
  
  force_delete = true

  tags = {
    Name = "Batch Satellite Brightness Repository"
    Environment = "dev"
  }
}

# ECR Lifecycle Policy to manage image versions
resource "aws_ecr_lifecycle_policy" "batch_satellite_brightness_policy" {
  repository = aws_ecr_repository.batch_satellite_brightness.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus = "any"
        countType = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Get ECR authorization token
data "aws_ecr_authorization_token" "token" {}

# Create a content-based tag for the container image
locals {
  image_tag = substr(sha256(join("", [
    filemd5("${path.module}/Dockerfile"),
    filemd5("${path.module}/requirements-batch.txt"), 
    filemd5("${path.module}/../src/aws_py_data_eng/batch_satellite_brightness.py")
  ])), 0, 8)
}

# Build and push Docker image using Podman
resource "null_resource" "batch_image_build" {
  # Rebuild when Dockerfile or source code changes
  triggers = {
    dockerfile_hash = filemd5("${path.module}/Dockerfile")
    requirements_hash = filemd5("${path.module}/requirements-batch.txt")
    source_code_hash = filemd5("${path.module}/../src/aws_py_data_eng/batch_satellite_brightness.py")
    repository_url = aws_ecr_repository.batch_satellite_brightness.repository_url
    image_tag = local.image_tag
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Authenticate with podman using Terraform-provided token
      echo ${data.aws_ecr_authorization_token.token.password} | podman login --username AWS --password-stdin ${data.aws_ecr_authorization_token.token.proxy_endpoint}
      
      # Build the image using podman with explicit platform
      podman build --platform linux/amd64 -t batch-satellite-brightness:${local.image_tag} -f ${path.module}/Dockerfile ${path.module}/../
      
      # Tag for ECR with content-based tag
      podman tag batch-satellite-brightness:${local.image_tag} ${aws_ecr_repository.batch_satellite_brightness.repository_url}:${local.image_tag}
      
      # Also tag as latest for convenience
      podman tag batch-satellite-brightness:${local.image_tag} ${aws_ecr_repository.batch_satellite_brightness.repository_url}:latest
      
      # Push both tags to ECR
      podman push ${aws_ecr_repository.batch_satellite_brightness.repository_url}:${local.image_tag}
      podman push ${aws_ecr_repository.batch_satellite_brightness.repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.batch_satellite_brightness]
}

# IAM Role for Batch Compute Environment Service Role
resource "aws_iam_role" "batch_service_role" {
  name = "BatchServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Batch Service Role"
  }
}

# IAM Role for Batch Task Execution (ECS Task Execution)
resource "aws_iam_role" "batch_execution_role" {
  name = "BatchTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Batch Task Execution Role"
  }
}

# IAM Role for Batch Job (Task Role)
resource "aws_iam_role" "batch_job_role" {
  name = "BatchJobRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Batch Job Role"
  }
}

# IAM Policy for Batch Job to access S3
resource "aws_iam_policy" "batch_s3_policy" {
  name        = "BatchSatelliteBrightnessS3Policy"
  description = "Policy for Batch job to access S3 buckets for satellite imagery processing"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.landing_zone.arn,
          "${aws_s3_bucket.landing_zone.arn}/*",
          "arn:aws:s3:::spacenet-dataset",
          "arn:aws:s3:::spacenet-dataset/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach AWS managed policy for Batch Service Role
resource "aws_iam_role_policy_attachment" "batch_service_role_attachment" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# Attach AWS managed policy for ECS Task Execution
resource "aws_iam_role_policy_attachment" "batch_execution_role_attachment" {
  role       = aws_iam_role.batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach custom S3 policy to job role
resource "aws_iam_role_policy_attachment" "batch_job_s3_policy_attachment" {
  role       = aws_iam_role.batch_job_role.name
  policy_arn = aws_iam_policy.batch_s3_policy.arn
}

# Batch Compute Environment (Fargate)
resource "aws_batch_compute_environment" "satellite_brightness_compute" {
  compute_environment_name = "satellite-brightness-fargate"
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role            = aws_iam_role.batch_service_role.arn

  compute_resources {
    type               = "FARGATE"
    max_vcpus          = 256
    security_group_ids = [aws_security_group.batch_security_group.id]
    subnets           = data.aws_subnets.default.ids
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service_role_attachment]

  tags = {
    Name = "Satellite Brightness Fargate Compute Environment"
    Environment = "dev"
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for Batch jobs
resource "aws_security_group" "batch_security_group" {
  name_prefix = "batch-satellite-brightness-"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Batch Satellite Brightness Security Group"
    Environment = "dev"
  }
}

# Batch Job Queue
resource "aws_batch_job_queue" "satellite_brightness_queue" {
  name                 = "satellite-brightness-queue"
  state               = "ENABLED"
  priority            = 1
  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.satellite_brightness_compute.arn
  }

  tags = {
    Name = "Satellite Brightness Job Queue"
    Environment = "dev"
  }
}

# Batch Job Definition
resource "aws_batch_job_definition" "satellite_brightness_job" {
  name = "satellite-brightness-job"
  type = "container"

  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = "${aws_ecr_repository.batch_satellite_brightness.repository_url}:${local.image_tag}"
    
    # High memory configuration for 12-15GB satellite imagery processing
    resourceRequirements = [
      {
        type  = "VCPU"
        value = "8"
      },
      {
        type  = "MEMORY"
        value = "32768"  # 32GB memory (exceeds Lambda's 10GB limit)
      }
    ]

    executionRoleArn = aws_iam_role.batch_execution_role.arn
    jobRoleArn      = aws_iam_role.batch_job_role.arn
    
    networkConfiguration = {
      assignPublicIp = "ENABLED"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-region" = data.aws_region.current.name
        "awslogs-stream-prefix" = "satellite-brightness"
      }
    }

    # Override default command to pass parameters
    command = [
      "python", 
      "-m", 
      "aws_py_data_eng.batch_satellite_brightness",
      "Ref::triggerBucket",
      "Ref::triggerKey"
    ]
  })

  parameters = {
    triggerBucket = ""
    triggerKey    = ""
  }

  retry_strategy {
    attempts = 1
  }

  timeout {
    attempt_duration_seconds = 3600  # 1 hour timeout
  }

  tags = {
    Name = "Satellite Brightness Job Definition"
    Environment = "dev"
  }
}

# CloudWatch Log Group for Batch jobs
resource "aws_cloudwatch_log_group" "batch_logs" {
  name              = "/aws/batch/satellite-brightness"
  retention_in_days = 7

  tags = {
    Name = "Batch Satellite Brightness Logs"
    Environment = "dev"
  }
}

# CloudWatch Log Group for EventBridge rule debugging
resource "aws_cloudwatch_log_group" "eventbridge_batch_logs" {
  name              = "/aws/events/rule/s3-config-upload-batch-trigger"
  retention_in_days = 7

  tags = {
    Name = "EventBridge Batch Rule Logs"
    Environment = "dev"
  }
}

# EventBridge rule to trigger Batch job on S3 text file uploads (batch/ prefix)
resource "aws_cloudwatch_event_rule" "s3_config_upload_batch" {
  name        = "s3-config-upload-batch-trigger"
  description = "Trigger Batch job when config text files are uploaded to batch/ prefix"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    detail-type   = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.landing_zone.bucket]
      }
      object = {
        key = [{
          prefix = "batch/"
        }, {
          suffix = ".txt"
        }]
      }
    }
  })

  tags = {
    Name = "S3 Config Upload Batch Trigger"
    Environment = "dev"
  }
}

# IAM role for EventBridge to submit Batch jobs
resource "aws_iam_role" "eventbridge_batch_role" {
  name = "EventBridgeBatchRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "EventBridge Batch Role"
  }
}

# Attach AWS managed policy for EventBridge Batch targets
resource "aws_iam_role_policy_attachment" "eventbridge_batch_service_policy" {
  role       = aws_iam_role.eventbridge_batch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceEventTargetRole"
}

# EventBridge target to submit Batch job
resource "aws_cloudwatch_event_target" "batch_target" {
  rule      = aws_cloudwatch_event_rule.s3_config_upload_batch.name
  target_id = "BatchJobTarget"
  arn       = aws_batch_job_queue.satellite_brightness_queue.arn
  role_arn  = aws_iam_role.eventbridge_batch_role.arn

  batch_target {
    job_definition = aws_batch_job_definition.satellite_brightness_job.name
    job_name       = "satellite-brightness"
  }

  input_transformer {
    input_paths = {
      bucketName = "$.detail.bucket.name"
      objectKey  = "$.detail.object.key"
    }
    
    input_template = <<-EOF
    {
      "Parameters": {
        "triggerBucket": "<bucketName>",
        "triggerKey": "<objectKey>"
      }
    }
    EOF
  }

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_batch_dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 1
    maximum_event_age_in_seconds = 300
  }
}

# SQS Dead Letter Queue for failed EventBridge Batch invocations
resource "aws_sqs_queue" "eventbridge_batch_dlq" {
  name = "eventbridge-batch-dlq"
  
  message_retention_seconds = 1209600  # 14 days
  
  tags = {
    Name = "EventBridge Batch DLQ"
    Environment = "dev"
  }
}

# Resource-based policy for EventBridge to send messages to DLQ
resource "aws_sqs_queue_policy" "eventbridge_batch_dlq_policy" {
  queue_url = aws_sqs_queue.eventbridge_batch_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgeDLQPermissions"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.eventbridge_batch_dlq.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_config_upload_batch.arn
          }
        }
      }
    ]
  })
}

# IAM policy for EventBridge to write to CloudWatch logs
resource "aws_cloudwatch_log_resource_policy" "eventbridge_logs_policy" {
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "delivery.logs.amazonaws.com"
          ]
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.eventbridge_batch_logs.arn}:*"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.s3_config_upload_batch.arn
          }
        }
      }
    ]
  })
  policy_name = "EventBridgeBatchLogsPolicy"
}

# Additional CloudWatch Logs target for debugging EventBridge invocations
resource "aws_cloudwatch_event_target" "batch_debug_logs" {
  rule      = aws_cloudwatch_event_rule.s3_config_upload_batch.name
  target_id = "DebugLogsTarget"
  arn       = aws_cloudwatch_log_group.eventbridge_batch_logs.arn
}