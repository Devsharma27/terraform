terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# crate a internet gateway
resource "aws_internet_gateway" "InternetGateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Internet-public"
  }
}

# create a 2 subnet public
resource "aws_subnet" "public1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "public-1"
  }
}
resource "aws_subnet" "public2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "public-2"
  }
}

# crate a public route table
resource "aws_route_table" "PublicRoute" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.InternetGateway.id
  }
  tags = {
    Name = "publicRouteTable"
  }
}

# route table associations
resource "aws_route_table_association" "a" {
  subnet_id = aws_subnet.public1.id
  route_table_id = aws_route_table.PublicRoute.id
}
resource "aws_route_table_association" "b" {
  subnet_id = aws_subnet.public2.id
  route_table_id = aws_route_table.PublicRoute.id
}


#crate a 2 private subnet
resource "aws_subnet" "Private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = "false"

  tags = {
    Name = "private-1"
  }
}
resource "aws_subnet" "Private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = "false"

  tags = {
    Name = "private-2"
  }
}
# crate a nat with a EIP
resource "aws_eip" "EIP" {
  # instance = aws_instance.EC2Instance.id

  tags = {
    Name = "eip"
  }
}
resource "aws_nat_gateway" "Natgateway" {
  depends_on = [aws_internet_gateway.InternetGateway]
  allocation_id = aws_eip.EIP.id
  subnet_id     = aws_subnet.public1.id

  tags = {
    Name = "NAT"
  }
}

# crate a private route table
resource "aws_route_table" "PrivateRoute" {
  depends_on = [aws_nat_gateway.Natgateway]
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.Natgateway.id
  }
  tags = {
    Name = "PrivateRouteTable"
  }
}

# Crate route table association
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.Private1.id
  route_table_id = aws_route_table.PrivateRoute.id
}
resource "aws_route_table_association" "d" {
  subnet_id     = aws_subnet.Private2.id
  route_table_id = aws_route_table.PrivateRoute.id
}

resource "aws_security_group" "ec2_security_group" {
  name        = "ec2_security_group"
  description = "Allow inbound traffic for ec2"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "EC2Instance" {
  depends_on = [aws_nat_gateway.Natgateway]
  instance_type = "t2.micro"
  ami           = "ami-04902260ca3d33422"
  subnet_id     = aws_subnet.Private1.id
  key_name      = "dev"
  iam_instance_profile = "ec2role"
  vpc_security_group_ids = ["${aws_security_group.ec2_security_group.id}"]
  user_data = <<-EOF
    #!/bin/bash
    sudo su
    sudo yum update -y
    sudo yum install python3-pip git mysql -y
    sudo git clone "https://github.com/Devsharma27/flask_test.git"
    sudo pip3 install flask
    cd /flask_test
    python3 app.py
  EOF
  tags = {
    Name = "Dev"
  }
}

#create a EC2 targate group
resource "aws_lb_target_group" "EC2_Target_Group" {
  depends_on = [aws_instance.EC2Instance]
  name     = "Target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "instance"
  
  health_check {    
    healthy_threshold   = 3    
    unhealthy_threshold = 10    
    timeout             = 5    
    interval            = 10 
    protocol            = "HTTP"   
  }
}

resource "aws_lb_target_group_attachment" "lb-target-group-attachment" {
  target_group_arn = aws_lb_target_group.EC2_Target_Group.arn
  target_id        = aws_instance.EC2Instance.id
  port             = 80
}

# create a alb listener
resource "aws_lb_listener" "ALB_Listener" {
  depends_on = [aws_instance.EC2Instance]
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.EC2_Target_Group.arn
  }
}

# Create a Application load balancer
resource "aws_security_group" "alb_security_group" {
  name        = "lb-security-group"
  description = "Allow inbound traffic for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ALB Security Group"
  }
}

resource "aws_lb" "lb" {
  depends_on = [aws_instance.EC2Instance]
  name               = "lb"
  internal = "false"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets = [
    "${aws_subnet.public1.id}",
    "${aws_subnet.public2.id}",
  ]
}
# Output
output "alb_dns_name" {
  value = "${aws_lb.lb.dns_name}"
}
