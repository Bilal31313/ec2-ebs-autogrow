# CloudWatch log group for our script
resource "aws_cloudwatch_log_group" "ebs_log" {
  name              = "/autogrow/ebs-monitor"
  retention_in_days = 30
}

# Ship /var/log/ebs-monitor.log via CW Agent
resource "aws_ssm_document" "ship_logs" {
  name          = "EBSAutoGrow-ShipLogs"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2",
    mainSteps = [{
      name   = "cwagent",
      action = "aws:runShellScript",
      inputs = {
        runCommand = [
          "cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'",
          jsonencode({
            logs = {
              logs_collected = {
                files = {
                  collect_list = [{
                    file_path       = "/var/log/ebs-monitor.log",
                    log_group_name  = "/autogrow/ebs-monitor",
                    log_stream_name = "{instance_id}"
                  }]
                }
              }
            }
          }),
          "EOF",
          "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop",
          "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s"
        ]
      }
    }]
  })
}

resource "aws_ssm_association" "attach_agent" {
  name = aws_ssm_document.ship_logs.name

  targets {
    key    = "InstanceIds"
    values = [aws_instance.autogrow_host.id]
  }
}

# Metric filter for "Threshold exceeded"
resource "aws_cloudwatch_log_metric_filter" "auto_events" {
  name           = "AutoGrowEvents"
  log_group_name = aws_cloudwatch_log_group.ebs_log.name
  pattern        = "Threshold exceeded"

  metric_transformation {
    name      = "AutoGrowEventCount"
    namespace = "EBSAutoGrow"
    value     = "1"
  }
}

# SNS topic & email subscription
resource "aws_sns_topic" "alerts" { name = "ebs-autogrow-alerts" }

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "bilalkhawaja04@outlook.com" 
# replace to endpoint to your email
}

# Alarm fires if an auto-grow event occurs
resource "aws_cloudwatch_metric_alarm" "grow_alarm" {
  alarm_name          = "EBS-AutoGrow-Triggered"
  metric_name         = aws_cloudwatch_log_metric_filter.auto_events.metric_transformation[0].name
  namespace           = "EBSAutoGrow"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
