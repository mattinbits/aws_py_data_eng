# AWS-provided awswrangler layer ARN
locals {
  awswrangler_layer_arn = "arn:aws:lambda:us-east-1:336392948345:layer:AWSSDKPandas-Python312:19"
}

# Create deployment package for Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_deployment.zip"
  source_dir  = "${path.module}/../src"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_csv_to_parquet_role" {
  name = "LambdaCsvToParquetRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Lambda CSV to Parquet Role"
  }
}

# IAM policy for Lambda to access S3
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "LambdaCsvToParquetS3Policy"
  description = "Policy for Lambda function to access S3 buckets"

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
          "${aws_s3_bucket.landing_zone.arn}/*"
        ]
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_csv_to_parquet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom S3 policy
resource "aws_iam_role_policy_attachment" "lambda_s3_policy_attachment" {
  role       = aws_iam_role.lambda_csv_to_parquet_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# Lambda function
resource "aws_lambda_function" "csv_to_parquet" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "csv-to-parquet-converter"
  role            = aws_iam_role.lambda_csv_to_parquet_role.arn
  handler         = "aws_py_data_eng.lambda_wrapper.lambda_handler"
  runtime         = "python3.12"
  timeout         = 300
  memory_size     = 512

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = [
    local.awswrangler_layer_arn
  ]

  environment {
    variables = {
      PYTHONPATH = "/var/runtime:/opt/python"
    }
  }

  tags = {
    Name = "CSV to Parquet Converter Lambda"
    Environment = "dev"
  }
}


# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_to_parquet.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.landing_zone.arn
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.csv_to_parquet.function_name}"
  retention_in_days = 7

  tags = {
    Name = "Lambda CSV to Parquet Logs"
    Environment = "dev"
  }
}