terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region  =  "us-east-1"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "terraformvpc"
  }
}

resource "aws_subnet" "pubsub1" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "publicsubnet"
  }
}

resource "aws_subnet" "pubsub2" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "publicsubnet"
  }
}

resource "aws_subnet" "privsub1" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "privatesubnet"
  }
}

resource "aws_subnet" "privsub2" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "privatesubnet"
  }
}

resource "aws_internet_gateway" "tigw" {
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "IGW"
  }
}

resource "aws_route_table" "pubrt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tigw.id
  }



  tags = {
    Name = "publicRT"
  }
}

resource "aws_route_table_association" "pubassociation1" {
  subnet_id      = aws_subnet.pubsub1.id
  route_table_id = aws_route_table.pubrt.id
}

resource "aws_route_table_association" "pubassociation2" {
  subnet_id      = aws_subnet.pubsub2.id
  route_table_id = aws_route_table.pubrt.id
}

resource "aws_eip" "eip" {
  vpc      = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.pubsub1.id
  tags = {
    Name = "natgw"
  }
}

resource "aws_route_table" "privrt" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }



  tags = {
    Name = "privateRT"
  }
}

resource "aws_route_table_association" "privassociation1" {
  subnet_id      = aws_subnet.privsub1.id
  route_table_id = aws_route_table.privrt.id
}

resource "aws_route_table_association" "privassociation2" {
  subnet_id      = aws_subnet.privsub2.id
  route_table_id = aws_route_table.privrt.id
}

resource "aws_security_group" "ec2SG" {
  name        = "ec2SG"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

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
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }


  tags = {
    Name = "EC2GS"
  }
}

resource "aws_instance" "EC2Instance" {
  depends_on   = ["aws_nat_gateway.nat"]
  depends_on   = ["aws_db_instance.default"]
  ami                         =  "ami-04902260ca3d33422"
  instance_type               =  "t2.micro"  
  subnet_id                   =  aws_subnet.privsub1.id
  key_name                    =  "srinath"
  vpc_security_group_ids      =  ["${aws_security_group.ec2SG.id}"]
  iam_instance_profile        =  "ec2role"  
  user_data = "${file("flask.sh")}"

  tags = {
    Name = "EC2instance"
  }
}

resource "aws_security_group" "ALBSG" {
  name        = "ALBSG"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

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
    Name = "allow_http"
  }
}

resource "aws_lb" "web_servers" {
  depends_on   = ["aws_instance.EC2Instance"]
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ALBSG.id]
  subnets            = [aws_subnet.pubsub1.id, aws_subnet.pubsub2.id]

  tags = {
    Name = "Application_load_balancer"
  }
}

resource "aws_lb_target_group" "ALBtargetgroup" {
  name     = "TargetGroup"
  port     = 80
  protocol = "HTTP"
  deregistration_delay = 20
  vpc_id   = aws_vpc.myvpc.id

  health_check {    
    healthy_threshold   = 5    
    unhealthy_threshold = 3    
    timeout             = 5    
    interval            = 10    
  }
}

resource "aws_lb_target_group_attachment" "TGattach" {
  target_group_arn = aws_lb_target_group.ALBtargetgroup.arn
  target_id        = aws_instance.EC2Instance.id
  port             = 80
}

resource "aws_lb_listener" "Listener" {
  depends_on   = ["aws_instance.EC2Instance"]
  load_balancer_arn = aws_lb.web_servers.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ALBtargetgroup.arn
  }
  
}

resource "aws_ebs_volume" "New_volume" {
  availability_zone = "us-east-1a"
  size              = 30

  tags = {
    Name = "HelloWorld"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.New_volume.id
  instance_id = aws_instance.EC2Instance.id
}

resource "aws_security_group" "rds" {
  name   = "RDSsg"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDSsg"
  }
}

resource "aws_db_subnet_group" "RDSsubnetgroup" {
  name       = "rdssubnetgroup"
  subnet_ids = [aws_subnet.privsub1.id, aws_subnet.privsub2.id]

  tags = {
    Name = "RDSsubnetgroup"
  }
}

resource "aws_db_instance" "default" {
  identifier             = "my-database"
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.RDSsubnetgroup.id
  engine                 = "mysql"
  instance_class         = "db.t2.micro"
  vpc_security_group_ids = [aws_security_group.rds.id]
  name                   = "mydb"
  username               = "admin"
  password               = "admin123"
  skip_final_snapshot    = false
}

resource "aws_s3_bucket" "s3bucket" {
  acl    = "private"

  tags = {
    Name        = "My bucket"
  }
}

resource "aws_sns_topic" "my_topic" {
  name = "user-updates-topic"
}

output "sns_arn" {
  value = "${aws_sns_topic.my_topic.arn}"
}

resource "aws_sns_topic_subscription" "SNSsubscription" {
  topic_arn = aws_sns_topic.my_topic.arn
  protocol  = "email"
  endpoint  = "srinathbala00@gmail.com"
}

resource "aws_cloudwatch_metric_alarm" "CPUalarm" {
  alarm_name                = "CPU-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120"
  statistic                 = "Average"
  threshold                 = "30"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.my_topic.arn]
  ok_actions          = [aws_sns_topic.my_topic.arn]
  dimensions = {
       InstanceId = aws_instance.EC2Instance.id
     }
}

resource "aws_cloudwatch_metric_alarm" "Memoryalarm" {
  alarm_name                = "Memory-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120"
  statistic                 = "Average"
  threshold                 = "30"
  alarm_description         = "This metric monitors ec2 memory utilization"
  alarm_actions       = [aws_sns_topic.my_topic.arn]
  ok_actions          = [aws_sns_topic.my_topic.arn]
  dimensions = {
       InstanceId = aws_instance.EC2Instance.id
     }
}
