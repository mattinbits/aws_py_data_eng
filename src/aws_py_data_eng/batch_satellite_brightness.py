"""
AWS Batch job for calculating city-wide brightness statistics from Las Vegas satellite imagery.
Demonstrates memory-intensive processing that exceeds Lambda's 10GB limit.
"""

import os
import json
import boto3
import numpy as np
import rasterio
from typing import List, Dict, Any


def demo_citywide_brightness_analysis(source_bucket: str = 'spacenet-dataset', 
                                     source_prefix: str = 'spacenet/SN2_buildings/train/AOI_2_Vegas/PS-RGB/') -> Dict[str, Any]:
    """
    Demo function that loads first 800 Las Vegas satellite images
    and calculates city-wide brightness statistics
    """
    # Get list of first 800 satellite images
    s3 = boto3.client('s3')
    
    print(f"Listing satellite images from s3://{source_bucket}/{source_prefix}")
    
    # List objects and get first 800
    response = s3.list_objects_v2(
        Bucket=source_bucket,
        Prefix=source_prefix,
        MaxKeys=1000  # Get more than 800 to ensure we have enough .tif files
    )
    
    # Build S3 paths for satellite images
    image_paths = []
    for obj in response.get('Contents', []):
        if obj['Key'].endswith('.tif') and 'PS-RGB_img' in obj['Key']:
            s3_path = f"s3://{source_bucket}/{obj['Key']}"
            image_paths.append(s3_path)
    
    # Take exactly 800 images to ensure memory failure on Lambda
    image_paths = image_paths[:800]
    
    print(f"Processing {len(image_paths)} Las Vegas satellite images...")
    print("This will exceed Lambda's 10GB memory limit but work on Batch with 32GB+")
    
    # This will exceed Lambda's 10GB memory limit
    return calculate_citywide_brightness(image_paths)


def calculate_citywide_brightness(image_paths: List[str]) -> Dict[str, Any]:
    """
    Calculate city-wide brightness statistics from satellite imagery.
    Requires loading ALL images simultaneously - exceeds Lambda memory limit.
    
    Args:
        image_paths: List of S3 paths to satellite images
        
    Returns:
        Dictionary containing brightness statistics
    """
    print(f"Loading {len(image_paths)} satellite images...")
    
    # Load ALL satellite images into memory simultaneously
    all_pixel_values = []
    
    for i, image_path in enumerate(image_paths):
        if i % 100 == 0:
            print(f"Loading image {i+1}/{len(image_paths)}")
        
        try:
            with rasterio.open(image_path) as src:
                image_data = src.read()  # ~15MB per image when loaded
                # Convert to grayscale and flatten  
                grayscale = np.mean(image_data, axis=0)
                all_pixel_values.append(grayscale.flatten())
        except Exception as e:
            print(f"Warning: Could not load {image_path}: {e}")
            continue
    
    if not all_pixel_values:
        raise ValueError("No valid satellite images could be loaded")
    
    # MEMORY FAILURE POINT: Concatenate all pixels (12GB+)
    print("Combining all pixel data into single array...")
    city_pixels = np.concatenate(all_pixel_values)
    print(f"Total pixels loaded: {len(city_pixels):,}")
    print(f"Memory usage: ~{len(city_pixels) * 8 / (1024**3):.1f} GB")
    
    # Simple calculations on full dataset
    print("Calculating city-wide statistics...")
    city_brightness = float(np.mean(city_pixels))
    city_contrast = float(np.std(city_pixels))
    brightness_percentiles = np.percentile(city_pixels, [25, 50, 75, 95])
    
    result = {
        "total_images_processed": len(image_paths),
        "total_pixels_analyzed": len(city_pixels),
        "city_average_brightness": city_brightness,
        "city_contrast_score": city_contrast,
        "brightness_percentiles": {
            "25th": float(brightness_percentiles[0]),
            "50th": float(brightness_percentiles[1]), 
            "75th": float(brightness_percentiles[2]),
            "95th": float(brightness_percentiles[3])
        },
        "memory_used_gb": len(city_pixels) * 8 / (1024**3)
    }
    
    print("Analysis complete!")
    return result


def parse_config_file(s3_bucket: str, config_key: str) -> Dict[str, str]:
    """
    Parse the configuration text file to get source bucket and prefix.
    
    Args:
        s3_bucket: Bucket containing the config file
        config_key: S3 key of the config file
        
    Returns:
        Dictionary with source_bucket and source_prefix
    """
    s3_client = boto3.client('s3')
    
    # Download and read the config file
    response = s3_client.get_object(Bucket=s3_bucket, Key=config_key)
    config_content = response['Body'].read().decode('utf-8').strip()
    
    print(f"Config file content: {config_content}")
    
    # Parse the S3 path (expected format: s3://bucket/prefix)
    if not config_content.startswith('s3://'):
        raise ValueError(f"Config file must contain S3 path starting with s3://. Got: {config_content}")
    
    # Remove s3:// and split bucket/prefix
    s3_path = config_content[5:]  # Remove 's3://'
    parts = s3_path.split('/', 1)
    
    source_bucket = parts[0]
    source_prefix = parts[1] if len(parts) > 1 else ''
    
    return {
        'source_bucket': source_bucket,
        'source_prefix': source_prefix
    }


def main():
    """
    Main entry point for AWS Batch job.
    Expects command line arguments for trigger file location.
    """
    try:
        import sys
        
        # Get parameters from command line arguments (passed by Batch)
        if len(sys.argv) < 3:
            raise ValueError("Usage: python -m aws_py_data_eng.batch_satellite_brightness <trigger_bucket> <trigger_key>")
        
        trigger_bucket = sys.argv[1]
        trigger_key = sys.argv[2]
        
        print(f"Received arguments: bucket={trigger_bucket}, key={trigger_key}")
        
        # Always auto-generate output key based on trigger file name
        base_name = os.path.splitext(os.path.basename(trigger_key))[0]
        output_s3_key = f"batch/results/{base_name}_brightness_analysis.json"
        
        print(f"Starting Las Vegas satellite imagery brightness analysis job")
        print(f"Trigger file: s3://{trigger_bucket}/{trigger_key}")
        print(f"Output: s3://{trigger_bucket}/{output_s3_key}")
        
        # Parse config file to get source data location
        config = parse_config_file(trigger_bucket, trigger_key)
        source_bucket = config['source_bucket']
        source_prefix = config['source_prefix']
        
        print(f"Source data: s3://{source_bucket}/{source_prefix}")
        
        # Run the memory-intensive brightness analysis
        result = demo_citywide_brightness_analysis(source_bucket, source_prefix)
        
        # Upload result to S3
        s3_client = boto3.client('s3')
        result_json = json.dumps(result, indent=2)
        
        s3_client.put_object(
            Bucket=trigger_bucket,
            Key=output_s3_key,
            Body=result_json,
            ContentType='application/json'
        )
        
        print(f"Results uploaded to s3://{trigger_bucket}/{output_s3_key}")
        print("Job completed successfully!")
        
        # Also print result to stdout for CloudWatch logs
        print("Final result:")
        print(result_json)
        
    except Exception as e:
        print(f"Job failed with error: {e}")
        raise


if __name__ == "__main__":
    main()