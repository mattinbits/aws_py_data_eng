# Combined S3 bucket notification configuration
# This resource handles both Lambda direct invocation and EventBridge notifications
resource "aws_s3_bucket_notification" "combined_notification" {
  bucket = aws_s3_bucket.landing_zone.id

  # Direct Lambda invocation for lambda/ prefix
  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_to_parquet.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "lambda/"
    filter_suffix       = ".csv"
  }

  # EventBridge for all events (used by Glue workflow with glue/ prefix filtering)
  eventbridge = true

  depends_on = [
    aws_lambda_permission.allow_s3
  ]
}