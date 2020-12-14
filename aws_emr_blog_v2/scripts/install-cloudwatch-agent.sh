#!/usr/bin/env bash

echo "***** Update *****"
sudo yum update -y

echo "***** Setup CloudWatch Logging *****"
sudo yum install -y awslogs

echo "***** Setup CloudWatch Agent *****"
sudo tee /etc/awslogs/awslogs.conf > /dev/null <<EOT
[general]
# Path to the CloudWatch Logs agent's state file. The agent uses this file to maintain
# client side state across its executions.
state_file = /var/lib/awslogs/agent-state
[ranger_audit]
datetime_format = %Y-%m-%d %H:%M:%S,%f
file = /var/log/ranger/audit/archive/*
buffer_duration = 500
log_stream_name = ranger-audit-{instance_id}
initial_position = start_of_file
log_group_name = rangeraudit
EOT
sudo service awslogs restart || true
sudo chkconfig awslogs on || true
