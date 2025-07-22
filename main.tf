variable "instance_count" {
  default = 2
}

# Use default VPC
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the default VPC (updated to aws_subnets with filter)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Security Group allowing HTTP inbound and all outbound
resource "aws_security_group" "web_sg" {
  name        = "web-sg"
  description = "Allow HTTP inbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
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
}

# EC2 instances with Apache installed
resource "aws_instance" "web" {
  count         = var.instance_count
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  subnet_id     = element(data.aws_subnets.default.ids, count.index)
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello from instance ${count.index + 1}" > /var/www/html/index.html
              EOF

  tags = {
    Name = "web-instance-${count.index + 1}"
  }
}

# Application Load Balancer
resource "aws_lb" "app_lb" {
  name               = "app-alb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.web_sg.id]
}

# Target Group for ALB
resource "aws_lb_target_group" "app_tg" {
  name     = "app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

# Listener for ALB on port 80
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Attach EC2 instances to the Target Group
resource "aws_lb_target_group_attachment" "web_instances" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

