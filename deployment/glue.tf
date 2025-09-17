# Get current AWS account ID
data "aws_caller_identity" "current" {}

# S3 bucket for Glue scripts and assets
resource "aws_s3_bucket" "glue_scripts" {
  bucket        = "${var.bucket_name}-glue-scripts"
  force_destroy = true

  tags = {
    Name        = "${var.bucket_name}-glue-scripts"
    Environment = "dev"
    Purpose     = "Glue Scripts and Assets"
  }
}

resource "aws_s3_bucket_versioning" "glue_scripts_versioning" {
  bucket = aws_s3_bucket.glue_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "glue_scripts_encryption" {
  bucket = aws_s3_bucket.glue_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts_pab" {
  bucket = aws_s3_bucket.glue_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the Glue script package to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/glue_wrapper.py"
  source = "${path.module}/glue_wrapper.py"
  etag   = filemd5("${path.module}/glue_wrapper.py")

  tags = {
    Name = "CSV to Parquet Glue Wrapper"
    Type = "Python"
  }
}

# Upload the original module as a dependency
resource "aws_s3_object" "csv_to_parquet_module" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/csv_to_parquet.py"
  source = "${path.module}/../aws_py_data_eng/csv_to_parquet.py"
  etag   = filemd5("${path.module}/../aws_py_data_eng/csv_to_parquet.py")

  tags = {
    Name = "CSV to Parquet Module"
    Type = "Python"
  }
}


# IAM role for Glue job
resource "aws_iam_role" "glue_job_role" {
  name = "GlueCsvToParquetJobRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Glue CSV to Parquet Job Role"
  }
}

# IAM policy for Glue job to access S3 buckets
resource "aws_iam_policy" "glue_s3_policy" {
  name        = "GlueCsvToParquetS3Policy"
  description = "Policy for Glue job to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.landing_zone.arn,
          "${aws_s3_bucket.landing_zone.arn}/*",
          aws_s3_bucket.glue_scripts.arn,
          "${aws_s3_bucket.glue_scripts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:/aws-glue/*"
      }
    ]
  })
}

# Attach AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Attach custom S3 policy
resource "aws_iam_role_policy_attachment" "glue_s3_policy_attachment" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

# Glue Python Shell job
resource "aws_glue_job" "csv_to_parquet" {
  name         = "csv-to-parquet-converter"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "4.0"
  max_capacity = "0.0625"
  max_retries  = 0
  timeout      = 2880

  command {
    name            = "pythonshell"
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.glue_script.key}"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--additional-python-modules"        = "awswrangler"
    "--extra-py-files"                   = "s3://${aws_s3_bucket.glue_scripts.bucket}/${aws_s3_object.csv_to_parquet_module.key}"
    "--TempDir"                         = "s3://${aws_s3_bucket.glue_scripts.bucket}/temp/"
    "--bucket-name"                     = aws_s3_bucket.landing_zone.bucket
    "--csv-key"                         = ""
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Name = "CSV to Parquet Converter"
    Environment = "dev"
  }
}

# EventBridge rule to trigger Glue job on S3 events
resource "aws_cloudwatch_event_rule" "s3_csv_upload" {
  name        = "s3-csv-upload-trigger"
  description = "Trigger Glue job when CSV files are uploaded to S3"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    detail-type   = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.landing_zone.bucket]
      }
      object = {
        key = [{
          suffix = ".csv"
        }]
      }
    }
  })

  tags = {
    Name = "S3 CSV Upload Trigger"
    Environment = "dev"
  }
}

# IAM role for EventBridge to start Glue jobs
resource "aws_iam_role" "eventbridge_glue_role" {
  name = "EventBridgeGlueJobRole"

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
    Name = "EventBridge Glue Job Role"
  }
}

# IAM policy for EventBridge to start Glue workflows
resource "aws_iam_policy" "eventbridge_glue_policy" {
  name        = "EventBridgeGlueWorkflowPolicy"
  description = "Policy for EventBridge to start Glue workflows"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:notifyEvent"
        ]
        Resource = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workflow/${aws_glue_workflow.csv_to_parquet_workflow.name}"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.eventbridge_dlq.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_glue_policy_attachment" {
  role       = aws_iam_role.eventbridge_glue_role.name
  policy_arn = aws_iam_policy.eventbridge_glue_policy.arn
}

# Glue workflow to wrap the job
resource "aws_glue_workflow" "csv_to_parquet_workflow" {
  name        = "csv-to-parquet-workflow"
  description = "Workflow to trigger CSV to Parquet conversion"

  tags = {
    Name = "CSV to Parquet Workflow"
    Environment = "dev"
  }
}

# Glue trigger to start the job within the workflow
resource "aws_glue_trigger" "csv_to_parquet_trigger" {
  name          = "csv-to-parquet-trigger"
  type          = "EVENT"
  workflow_name = aws_glue_workflow.csv_to_parquet_workflow.name

  actions {
    job_name = aws_glue_job.csv_to_parquet.name
  }

  tags = {
    Name = "CSV to Parquet Trigger"
    Environment = "dev"
  }
}

# SQS Dead Letter Queue for failed EventBridge invocations
resource "aws_sqs_queue" "eventbridge_dlq" {
  name = "eventbridge-glue-workflow-dlq"
  
  tags = {
    Name = "EventBridge Glue Workflow DLQ"
    Environment = "dev"
  }
}

# EventBridge target to start Glue workflow
resource "aws_cloudwatch_event_target" "glue_workflow_target" {
  rule      = aws_cloudwatch_event_rule.s3_csv_upload.name
  target_id = "GlueWorkflowTarget"
  arn       = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workflow/${aws_glue_workflow.csv_to_parquet_workflow.name}"
  role_arn  = aws_iam_role.eventbridge_glue_role.arn

  dead_letter_config {
    arn = aws_sqs_queue.eventbridge_dlq.arn
  }

  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 300
  }

  # Remove input_transformer for now - Glue workflows might not support it
  # The job will use the default arguments instead
}

# S3 bucket notification to EventBridge
resource "aws_s3_bucket_notification" "eventbridge_notification" {
  bucket      = aws_s3_bucket.landing_zone.id
  eventbridge = true
}

# CloudWatch log group for Glue job
resource "aws_cloudwatch_log_group" "glue_job_logs" {
  name              = "/aws-glue/jobs/${aws_glue_job.csv_to_parquet.name}"
  retention_in_days = 7

  tags = {
    Name = "Glue CSV to Parquet Job Logs"
    Environment = "dev"
  }
}