terraform { 
required_providers { 
aws = { 
source  = "hashicorp/aws"
version = "~> 4.0"
} 
} 
} 
# set use of default profile in ~/.aws/credentials
provider "aws" {
  region = "eu-west-3"
  profile = "default"
}
#create aws vpc
resource "aws_vpc" "vpc_1" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags={
    terraform = "true"
    Name = "vpc_1"
  }
}
#create aws subnet
resource "aws_subnet" "main" {
  vpc_id     = aws_vpc.vpc_1.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "subnet1_vpc1"
  }
}
#create aws internet gateway , for access with ssh from internet
resource "aws_internet_gateway" "ck-jog-gw" {
  vpc_id = aws_vpc.vpc_1.id
  tags={
    Name = "ec2_ck_jog-gw"
  }
}
#create aws route table , for access with ssh from internet
resource "aws_route_table" "route-table-ck-jog" {
  vpc_id = aws_vpc.vpc_1.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ck-jog-gw.id
  }
  tags={
    Name = "route-table-ck-jog"
  }
}
#create aws route table association , for access with ssh from internet
resource "aws_route_table_association" "subnet-ck-jog-association" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.route-table-ck-jog.id
}
#create aws ec2 web server security group 
resource "aws_security_group" "ec2_security_group" {
  description =  "allow web services"
  vpc_id = aws_vpc.vpc_1.id
  ingress = [ {
    cidr_blocks = [ "0.0.0.0/0" ]
    description = "http access"
    from_port = 80
    protocol = "tcp"
    to_port = 80
    self = false
    prefix_list_ids =[]
    ipv6_cidr_blocks = []
    security_groups =[]
  },
  {
    cidr_blocks = [ "","","" ]
    description = "ssh access"
    from_port = 22
    protocol = "tcp"
    to_port = 22
    self = false
    prefix_list_ids =[]
    ipv6_cidr_blocks = [""]
    security_groups =[]
  }
  ]
  egress = [ {
    cidr_blocks = [ "0.0.0.0/0" ]
    description = "egress route"
    from_port = 0
    protocol = "-1"
    to_port = 0
    self = false
    prefix_list_ids =[]
    ipv6_cidr_blocks = []
    security_groups =[]
  } ]
  tags = {
    Name = "ec2_web"
  }
}
#define ec2 instance ami to use for creating ec2 instance
data "aws_ami" "amazon_linux_1"{
  most_recent = true
  owners = ["amazon"]
  filter{
    name = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name = "name"
    values = ["RHEL-8.6.0_HVM-20220503-x86_64-2-Hourly2-GP2"]
  }
}
#define launch config for auto scale groupe
resource "aws_launch_configuration" "ck-jog-launch_configuration" {
  image_id        = data.aws_ami.amazon_linux_1.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.ec2_security_group.id]
 
  user_data = <<-EOF
              #!/bin/bash
              yum -y install httpd
              echo "Hello, from auto-scaling group" > /var/www/html/index.html
              service httpd start
              chkconfig httpd on
              EOF
 
  lifecycle {
    create_before_destroy = true
  }
}
#define autoscalling group for autoscaling using launch config
resource "aws_autoscaling_group" "autockjog" {
  name                 = "ck-jog-autoscale"
  launch_configuration = aws_launch_configuration.ck-jog-launch_configuration.name
  vpc_zone_identifier  = [aws_subnet.main.id]
  health_check_type    = "ELB"
 
  min_size         = 1
  max_size         = 3
  desired_capacity = 2
 
  tag {
    key                 = "Name"
    value               = "ck-jog-autoscale"
    propagate_at_launch = true
  }
}
#define ec2 instance 1
resource "aws_instance" "ec2_instance1"{
  ami =  data.aws_ami.amazon_linux_1.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  key_name = "ec2_jog_ck2"
  associate_public_ip_address = true
  tags = {
    Name = "ec2_web"
  }
}
#define ec2 instance 2
resource "aws_instance" "ec2_instance2"{
  ami =  data.aws_ami.amazon_linux_1.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]
  key_name = "ec2_jog_ck2"
  associate_public_ip_address = true
  tags = {
    Name = "ec2_web"
  }
}
# define rds db mysql
resource "aws_db_instance" "default" {
  allocated_storage    = 10
  max_allocated_storage = 100
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}
# define different security group db sg including previous security group
resource "aws_security_group" "db_sg" {
  name = "db_sg"
  description = "Security group for db"
  vpc_id = aws_vpc.vpc_1.id
  ingress {
    description = "ingress mysql"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.ec2_security_group.id]
  }
  tags = {
    Name = "db_sg"
  }
}
#define S3 bucket 
resource "aws_s3_bucket" "ck_jog_bucket" {
  bucket = "ckjogbucket"

  tags = {
    Name        = "s3_g13"
    Environment = "Dev"
  }
}
# make use of s3 bucket for the site green.com
resource "aws_cloudfront_distribution" "tf" {
  origin {
    domain_name = aws_s3_bucket.ck_jog_bucket.bucket_regional_domain_name
    origin_id = "www.green.com"
    custom_origin_config {
      http_port = "80"
      https_port = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress = true
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = "www.green.com"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    ssl_support_method = "sni-only"
  }
}
resource "aws_cloudwatch_dashboard" "EC2_Dashboard" {
  dashboard_name = "EC2-jog-ck-Dashboard"

  dashboard_body = <<EOF
{
    "widgets": [
        {
            "type": "explorer",
            "width": 24,
            "height": 15,
            "x": 0,
            "y": 0,
            "properties": {
                "metrics": [
                    {
                        "metricName": "CPUUtilization",
                        "resourceType": "AWS::EC2::Instance",
                        "stat": "Maximum"
                    }
                ],
                "aggregateBy": {
                    "key": "InstanceType",
                    "func": "MAX"
                },
                "labels": [
                    {
                        "key": "State",
                        "value": "running"
                    }
                ],
                "widgetOptions": {
                    "legend": {
                        "position": "bottom"
                    },
                    "view": "timeSeries",
                    "rowsPerPage": 8,
                    "widgetsPerRow": 2
                },
                "period": 60,
                "title": "Running EC2 Instances CPUUtilization"
            }
        }
    ]
}
EOF
}


# Creating the AWS CLoudwatch Alarm that will autoscale the AWS EC2 instance based on CPU utilization.
resource "aws_cloudwatch_metric_alarm" "EC2_CPU_Usage_Alarm" {
# defining the name of AWS cloudwatch alarm
  alarm_name          = "EC2_CPU_Usage_Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
# Defining the metric_name according to which scaling will happen (based on CPU) 
  metric_name = "CPUUtilization"
# The namespace for the alarm's associated metric
  namespace = "AWS/EC2"
# After AWS Cloudwatch Alarm is triggered, it will wait for 60 seconds and then autoscales
  period = "60"
  statistic = "Average"
# CPU Utilization threshold is set to 10 percent
  threshold = "70"
alarm_description     = "This metric monitors ec2 cpu utilization exceeding 70%"
}
resource "aws_cloudwatch_composite_alarm" "EC2" {
  alarm_description = "Composite alarm that monitors CPUUtilization "
  alarm_name        = "EC2_Composite_Alarm"
  alarm_actions = [aws_sns_topic.EC2_topic.arn]

  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.EC2_CPU_Usage_Alarm.alarm_name})"

  depends_on = [
    aws_cloudwatch_metric_alarm.EC2_CPU_Usage_Alarm,
    aws_sns_topic.EC2_topic,
    aws_sns_topic_subscription.EC2_Subscription
  ]
}
resource "aws_cloudwatch_log_group" "ebs_log_group" {
  name = "ebs_log_group"
  retention_in_days = 30
}


resource "aws_cloudwatch_log_stream" "ebs_log_stream" {
  name           = "ebs_log_stream"
  log_group_name = aws_cloudwatch_log_group.ebs_log_group.name
}


resource "aws_sns_topic" "EC2_topic" {
  name = "EC2_topic"
}

resource "aws_sns_topic_subscription" "EC2_Subscription" {
  topic_arn = aws_sns_topic.EC2_topic.arn
  protocol  = "email"
  endpoint  = "automateinfra@gmail.com"

  depends_on = [
    aws_sns_topic.EC2_topic
  ]
}
#Outputs to get mandatory info.
output "database_endpoints" {
  description = "database endpoint"
  value = aws_db_instance.default.address
}
output "public_ipv4_address_ec2" {
  value = aws_instance.ec2_instance2.public_ip
}
output "public_ipv4_address_ec1" {
  value = aws_instance.ec2_instance1.public_ip
}
