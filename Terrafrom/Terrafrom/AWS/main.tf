provider "aws" {
  region = "ap-southeast-1"
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "public-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-igw"
  }
}

# Create Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Create 3 Public Subnets across 3 AZs
resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# Associate subnets with the public route table
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_ami" "ubuntu" {
  most_recent = true


  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # You can restrict this if desired
  }

  ingress {
    description = "Allow SSH for management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-sg"
  }
}


resource "aws_launch_template" "ec2_template" {
  name_prefix   = "ec2-autoscale-template-"
  image_id      = "ami-0c1907b6d738188e5"
  instance_type = "t3.medium"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }


  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Provision started at $(date)" >> /var/log/provision.log
              apt-get update -y
              apt-get install nginx -y
              systemctl enable nginx
              systemctl start nginx
              echo "Provision finished at $(date)" >> /var/log/provision.log
            EOF
  )


  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ec2_asg" {
  name                      = "ec2-asg"
  min_size                  = 3
  max_size                  = 5
  desired_capacity          = 3
  vpc_zone_identifier       = aws_subnet.public[*].id # 3 public subnets in different AZs
  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.ec2_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.ec2_tg.arn]

  tag {
    key                 = "Name"
    value               = "autoscaled-ec2"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_security_group" "lb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
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
    Name = "alb-sg"
  }
}
resource "aws_lb" "ec2_alb" {
  name               = "ec2-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "ec2-alb"
  }
}

resource "aws_lb_target_group" "ec2_tg" {
  name     = "ec2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "ec2-tg"
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out"
  autoscaling_group_name = aws_autoscaling_group.ec2_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 60
  alarm_description   = "This metric monitors high CPU usage"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.ec2_asg.name
  }
  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.ec2_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_tg.arn
  }
}
