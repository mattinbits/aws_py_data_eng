"""AWS Lambda wrapper for CSV to Parquet conversion triggered by S3 events."""

import json
import urllib.parse
from typing import Dict, Any
from aws_py_data_eng.csv_to_parquet import convert_csv_to_parquet


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for direct S3 events to convert CSV to Parquet.
    
    Args:
        event: S3 event containing object details
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    try:
        # Process each record in the S3 event
        results = []
        
        for record in event.get('Records', []):
            # Extract bucket and object key from S3 event
            s3_info = record.get('s3', {})
            bucket = s3_info.get('bucket', {}).get('name')
            object_key = s3_info.get('object', {}).get('key')
            
            if not bucket or not object_key:
                raise ValueError("Missing bucket name or object key in S3 event record")
            
            # URL decode the object key (S3 keys are URL encoded in events)
            object_key = urllib.parse.unquote_plus(object_key)
            
            print(f"Processing CSV file: {object_key} from bucket: {bucket}")
            
            # Convert CSV to Parquet
            parquet_key = convert_csv_to_parquet(bucket, object_key)
            
            results.append({
                'source_file': object_key,
                'output_file': parquet_key,
                'bucket': bucket,
                'status': 'success'
            })
            
            print(f"Successfully converted {object_key} to {parquet_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(results)} files',
                'results': results
            })
        }
        
    except Exception as e:
        error_message = f"Failed to process S3 event: {str(e)}"
        print(f"Error: {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'event': event
            })
        }


# For local testing
if __name__ == "__main__":
    # Sample S3 event for testing
    test_event = {
        'Records': [
            {
                's3': {
                    'bucket': {
                        'name': 'test-bucket'
                    },
                    'object': {
                        'key': 'lambda/test.csv'
                    }
                }
            }
        ]
    }
    
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))