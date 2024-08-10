Step for deployment:

1. create a customer-managed VPC or reuse existing one.
2. Create cross account IAM role for Databricks
3. Create S3 bucket and grant access to Databricks via Bucket Policy
4. Fill in paramaters defined in Terraform.tfvars
5. export AWS_ACCESS_KEY=xxx export AWS_SECRET_ACCESS_KEY=xxxx
6. terraform init
7. terraform apply
8. terraform destory to clean up whole enviornment
