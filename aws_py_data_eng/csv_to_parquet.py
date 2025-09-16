"""Convert CSV files from S3 to Parquet format with appropriate typing and column naming."""

import re
import awswrangler as wr
import pandas as pd


def clean_column_name(column_name: str) -> str:
    """Convert column name to snake_case without special characters."""
    # Remove special characters except spaces and alphanumeric
    cleaned = re.sub(r'[^\w\s]', '', column_name)
    # Replace spaces with underscores and convert to lowercase
    snake_case = re.sub(r'\s+', '_', cleaned.strip()).lower()
    return snake_case


def convert_csv_to_parquet(bucket: str, csv_key: str) -> str:
    """
    Read CSV from S3, apply appropriate types, clean column names, and save as Parquet.
    
    Args:
        bucket: S3 bucket name
        csv_key: S3 key for the CSV file
        
    Returns:
        S3 key for the created Parquet file
    """
    # Read CSV from S3
    s3_csv_path = f"s3://{bucket}/{csv_key}"
    df = wr.s3.read_csv(s3_csv_path)
    
    # Clean column names
    df.columns = [clean_column_name(col) for col in df.columns]
    
    # Apply appropriate data types based on the medical imaging dataset structure
    type_mapping = {
        'image_index': 'string',
        'finding_labels': 'string', 
        'follow_up': 'int64',
        'patient_id': 'int64',
        'patient_age': 'int64',
        'patient_gender': 'category',
        'view_position': 'category',
        'originalimagewidth': 'int64',
        'originalimageheight': 'int64',
        'originalimagepixelspacingx': 'float64',
        'originalimagepixelspacingy': 'float64'
    }
    
    # Apply types only for columns that exist in the dataframe
    for col, dtype in type_mapping.items():
        if col in df.columns:
            if dtype == 'category':
                df[col] = df[col].astype('category')
            elif dtype == 'int64':
                df[col] = pd.to_numeric(df[col], errors='coerce').astype('Int64')
            elif dtype == 'float64':
                df[col] = pd.to_numeric(df[col], errors='coerce')
            elif dtype == 'string':
                df[col] = df[col].astype('string')
    
    # Create parquet key by replacing .csv with .parquet
    parquet_key = csv_key.replace('.csv', '.parquet')
    s3_parquet_path = f"s3://{bucket}/{parquet_key}"
    
    # Write to S3 as Parquet
    wr.s3.to_parquet(
        df=df,
        path=s3_parquet_path,
        index=False,
        compression='snappy'
    )
    
    return parquet_key


def main():
    """Example usage of the CSV to Parquet conversion."""
    bucket_name = "adc-mjl-landing-zone"
    csv_file = "Data_Entry_2017.csv"
    
    try:
        parquet_key = convert_csv_to_parquet(bucket_name, csv_file)
        print(f"Successfully converted {csv_file} to {parquet_key}")
    except Exception as e:
        print(f"Error converting file: {e}")


if __name__ == "__main__":
    main()