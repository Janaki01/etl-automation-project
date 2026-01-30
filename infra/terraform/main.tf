provider "aws" {
  region = var.region
}
data "archive_file" "etl_lambda_zip" {
  type = "zip"
  source_dir = "${path.module}/../../lambda"
  output_path = "${path.module}/etl_lambda.zip"
}
# -------------------------------
# Security Group for RDS + Lambda
# -------------------------------
resource "aws_security_group" "etl_sg" {
  name        = "etl-sg-${var.env}"
  description = "Allow PostgreSQL access"
 
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # For demo only
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
 
# -------------------------------
# RDS PostgreSQL
# -------------------------------
resource "aws_db_instance" "etl_db" {
  identifier        = "etl-postgres-db-${var.env}"
  engine            = "postgres"
  engine_version    = "14.15"
  instance_class    = "db.t3.small"
  allocated_storage = 20
 
  db_name  = var.db_name
  username = var.db_user
  password = var.db_master_password
 
  publicly_accessible = true
  skip_final_snapshot = true
 
  vpc_security_group_ids = [aws_security_group.etl_sg.id]
}
 
# -------------------------------
# IAM Role for Lambda
# -------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "etl_lambda_role-${var.env}"
 
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
 
# -------------------------------
# Lambda Function (Simple test)
# -------------------------------
resource "aws_lambda_function" "etl_lambda" {
  function_name = "etl_automation_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  filename      = "${path.module}/etl_lambda.zip"
  # source_code_hash = filebase64sha256("${path.module}/etl_lambda.zip")
  # filename = data.archive_file.etl_lambda_zip.output_path
  # source_code_hash = data.archive_file.etl_lambda_zip.output_base64sha256
  timeout = 300
  memory_size = 512
 
  environment {
    variables = {
      DB_HOST     = aws_db_instance.etl_db.address
      DB_PORT     = "5432"
      DB_NAME     = "etl_db"
      DB_USER     = "etladmin"
      DB_PASSWORD = "Info!1808"
      S3_BUCKET = "etl-report-bucket-janaki"
    }
  }
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "etl_lambda_s3_policy"
  role = aws_iam_role.lambda_role.id
 
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = "arn:aws:s3:::etl-report-bucket-janaki/*"
      }
    ]
  })
}
resource "aws_iam_policy" "lambda_secrets_policy" {
  name = "lambda-secrets-access-${var.env}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement =[ 
      {
        Effect= "Allow"
        Action = [ "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
  
}

