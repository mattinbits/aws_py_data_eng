resource "aws_s3_bucket" "landing_zone" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = var.bucket_name
    Environment = "dev"
    Purpose     = "Data Engineering Landing Zone"
  }
}

resource "aws_s3_bucket_versioning" "landing_zone_versioning" {
  bucket = aws_s3_bucket.landing_zone.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "landing_zone_encryption" {
  bucket = aws_s3_bucket.landing_zone.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "landing_zone_pab" {
  bucket = aws_s3_bucket.landing_zone.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "landing_zone_ssl_only" {
  bucket = aws_s3_bucket.landing_zone.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.landing_zone.arn,
          "${aws_s3_bucket.landing_zone.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Create S3 folder structure for different processing workflows
resource "aws_s3_object" "lambda_folder" {
  bucket = aws_s3_bucket.landing_zone.id
  key    = "lambda/"
  source = "/dev/null"
  
  tags = {
    Name = "Lambda Processing Folder"
    Type = "Folder"
  }
}

resource "aws_s3_object" "glue_folder" {
  bucket = aws_s3_bucket.landing_zone.id
  key    = "glue/"
  source = "/dev/null"
  
  tags = {
    Name = "Glue Processing Folder"
    Type = "Folder"
  }
}

resource "aws_s3_object" "batch_folder" {
  bucket = aws_s3_bucket.landing_zone.id
  key    = "batch/"
  source = "/dev/null"
  
  tags = {
    Name = "Batch Processing Folder"
    Type = "Folder"
  }
}

resource "aws_s3_object" "batch_results_folder" {
  bucket = aws_s3_bucket.landing_zone.id
  key    = "batch/results/"
  source = "/dev/null"
  
  tags = {
    Name = "Batch Results Folder"
    Type = "Folder"
  }
}