"""Glue job wrapper for the CSV to Parquet conversion module."""

import sys
from awsglue.utils import getResolvedOptions

# Import the existing module
import csv_to_parquet


def main():
    """Glue job entry point that calls the existing csv_to_parquet module."""
    
    # Get job arguments including S3 details passed from Step Functions
    args = getResolvedOptions(sys.argv, ['bucket_name', 'csv_key'])
    bucket_name = args['bucket_name']
    csv_key = args['csv_key']
    
    print("Starting CSV to Parquet conversion job")
    print(f"Processing file: s3://{bucket_name}/{csv_key}")
    
    try:
        # Call the existing conversion function
        parquet_key = csv_to_parquet.convert_csv_to_parquet(bucket_name, csv_key)
        print(f"Job completed successfully. Created: {parquet_key}")
    except Exception as e:
        print(f"Job failed with error: {e}")
        raise


if __name__ == "__main__":
    main()