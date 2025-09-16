# AWS Python Data Engineering

A demonstration project showcasing serverless Python data engineering workflows using AWS services.

## Project Structure

```
├── aws_py_data_eng/     # Python package
│   ├── __init__.py
│   └── main.py          # Hello world entry point
├── deployment/          # Terraform infrastructure
│   ├── main.tf          # Provider configuration
│   ├── variables.tf     # Input variables
│   └── s3.tf           # S3 bucket resources
├── pyproject.toml       # Python project configuration
└── README.md
```

## Quick Start

### Python Application

1. Install dependencies:
   ```bash
   pip install -e .
   ```

2. Run the application:
   ```bash
   python -m aws_py_data_eng.main
   # or
   data-eng
   ```

### Infrastructure Deployment

1. Navigate to deployment directory:
   ```bash
   cd deployment
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Plan and apply infrastructure:
   ```bash
   terraform plan
   terraform apply
   ```

## Infrastructure

- **S3 Bucket**: `adc-mjl-landing-zone` in `eu-central-1`
  - Versioning enabled
  - AES256 encryption
  - SSL-only access policy
  - Public access blocked

## Dependencies

- Python 3.9+
- awswrangler
- Terraform >= 1.0
- AWS CLI configured