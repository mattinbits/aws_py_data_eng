"""Glue job wrapper for the CSV to Parquet conversion module."""

import sys
from awsglue.utils import getResolvedOptions

# Import the existing module
import csv_to_parquet


def main():
    """Glue job entry point that calls the existing csv_to_parquet module."""
    # Get job parameters from Glue
    args = getResolvedOptions(sys.argv, ['JOB_NAME', 'bucket-name', 'csv-key'])
    
    job_name = args['JOB_NAME']
    bucket_name = args['bucket-name']
    csv_key = args['csv-key']
    
    print(f"Starting Glue job: {job_name}")
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