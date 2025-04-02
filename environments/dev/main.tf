provider "aws" {
  region = "ap-northeast-2"
}

# VPC
module "vpc" {
  source = "../../modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
}

# 보안 그룹 - EC2용 (SSH, HTTP)
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# EC2 인스턴스
module "ec2" {
  source              = "../../modules/ec2"
  project_name        = var.project_name
  name                = "webserver"
  ami_id              = var.ami_id
  instance_type       = var.instance_type
  subnet_id           = module.vpc.public_subnet_ids[0]
  security_group_ids  = [aws_security_group.ec2_sg.id]
  key_name            = var.key_name
  associate_public_ip = true
  user_data           = file("${path.module}/user_data.sh")
  environment         = var.environment
}

# S3
module "s3" {
  source              = "../../modules/s3"
  project_name        = var.project_name
  name                = "static-assets"
  environment         = var.environment
  versioning_enabled  = true
  enable_sse          = true
  force_destroy       = true
}

# 보안 그룹 - ALB용
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP to ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ALB
module "alb" {
  source                    = "../../modules/alb"
  project_name              = var.project_name
  name                      = "app"
  environment               = var.environment
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.public_subnet_ids
  security_group_ids        = [aws_security_group.alb_sg.id]
  target_port               = 80
  target_protocol           = "HTTP"
  health_check_path         = "/"
  health_check_protocol     = "HTTP"
  enable_deletion_protection = false
  internal                  = false
}

# route 53
#module "route53" {
#  source = "../../modules/route53"

#  zone_id             = var.route53_zone_id                       # Route 53 Hosted Zone ID
#  record_name         = "app.${var.route53_domain_name}"          # 예: app.dev.example.com
#  record_type         = "A"
#  ttl                 = 300
#  alb_dns_name        = module.alb.alb_dns_name
#  depends_on_resource = module.alb
#}

# waf
module "waf" {
  source         = "../../modules/waf"
  project_name   = var.project_name
  name           = "web"
  environment    = var.environment
  scope          = "REGIONAL"
  alb_arn        = module.alb.alb_arn
  associate_alb  = true
}


