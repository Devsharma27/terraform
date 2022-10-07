#!/bin/bash
sudo yum update -y
sudo yum install python3-pip git mysql -y
sudo rpm -Uvh https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo aws s3 cp s3://my-cwagent-config-file/CloudWatchAgentConfig.json /opt/aws/amazon-cloudwatch-agent/CloudWatchAgentConfig.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/CloudWatchAgentConfig.json
sudo /bin/systemctl restart amazon-cloudwatch-agent.service
sudo git clone "https://github.com/SrinathBala/flask.git"
sudo pip3 install flask
sudo yum -y install python python3-devel mysql-devel redhat-rpm-config gcc
sudo pip3 install flask_mysqldb
sudo pip3 install mysql-connector-python
cd /flask
sudo python3 app.py
sudo /bin/systemctl restart amazon-cloudwatch-agent.service
