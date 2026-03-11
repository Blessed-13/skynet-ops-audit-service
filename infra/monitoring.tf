# ── CloudWatch Alarm — High Error Rate ───────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.app_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5 # alert if more than 5 errors in 1 minute
  alarm_description   = "More than 5 HTTP 5xx errors in 1 minute — investigate immediately"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  tags = { Name = "${var.app_name}-error-alarm" }
}

# ── CloudWatch Alarm — High Latency ──────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.app_name}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1 # alert if avg response > 1 second
  alarm_description   = "Average response time exceeded 1s — check DB or container performance"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  tags = { Name = "${var.app_name}-latency-alarm" }
}

# ── CloudWatch Alarm — Service Health (unhealthy hosts) ───────────────────────
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.app_name}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0 # alert immediately if any host is unhealthy
  alarm_description   = "ECS task is failing health checks — service may be down"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }

  tags = { Name = "${var.app_name}-health-alarm" }
}

# ── AWS Budget Alert ──────────────────────────────────────────────────────────
resource "aws_budgets_budget" "monthly" {
  name         = "${var.app_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80 # alert at 80% of budget
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["ops@airman.example.com"] # replace with real email
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["ops@airman.example.com"]
  }
}
