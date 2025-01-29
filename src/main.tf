locals {
  google_credentials         = one(data.aws_ssm_parameter.google_credentials[*].value)
  scim_endpoint_url          = one(data.aws_ssm_parameter.scim_endpoint_url[*].value)
  scim_endpoint_access_token = one(data.aws_ssm_parameter.scim_endpoint_access_token[*].value)
  identity_store_id          = one(data.aws_ssm_parameter.identity_store_id[*].value)
}

data "aws_ssm_parameter" "google_credentials" {
  name  = "${var.google_credentials_ssm_path}/google_credentials"
}

data "aws_ssm_parameter" "scim_endpoint_url" {
  name  = "${var.google_credentials_ssm_path}/scim_endpoint_url"
}

data "aws_ssm_parameter" "scim_endpoint_access_token" {
  name  = "${var.google_credentials_ssm_path}/scim_endpoint_access_token"
}

data "aws_ssm_parameter" "identity_store_id" {
  name  = "${var.google_credentials_ssm_path}/identity_store_id"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/dist/ssosync"
  output_path = "${path.module}/dist/ssosync.zip"
}


resource "aws_lambda_function" "ssosync" {
  function_name    = "${var.name}-function"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_sha256
  description      = "Syncs Google Workspace users and groups to AWS SSO"
  role             = aws_iam_role.default.arn
  handler          = "ssosync"
  runtime          = "go1.x"
  timeout          = 300
  memory_size      = 128

  environment {
    variables = {
      SSOSYNC_LOG_LEVEL          = var.log_level
      SSOSYNC_LOG_FORMAT         = var.log_format
      SSOSYNC_GOOGLE_CREDENTIALS = local.google_credentials
      SSOSYNC_GOOGLE_ADMIN       = var.google_admin_email
      SSOSYNC_SCIM_ENDPOINT      = local.scim_endpoint_url
      SSOSYNC_SCIM_ACCESS_TOKEN  = local.scim_endpoint_access_token
      SSOSYNC_REGION             = var.region
      SSOSYNC_IDENTITY_STORE_ID  = local.identity_store_id
      SSOSYNC_USER_MATCH         = var.google_user_match
      SSOSYNC_GROUP_MATCH        = var.google_group_match
      SSOSYNC_SYNC_METHOD        = var.sync_method
      SSOSYNC_IGNORE_GROUPS      = var.ignore_groups
      SSOSYNC_IGNORE_USERS       = var.ignore_users
      SSOSYNC_INCLUDE_GROUPS     = var.include_groups
      SSOSYNC_LOAD_ASM_SECRETS   = false
    }
  }
  depends_on = [data.archive_file.lambda]
}

resource "aws_cloudwatch_event_rule" "ssosync" {
  name                = "${var.name}-event-rule"
  description         = "Run ssosync on a schedule"
  schedule_expression = var.schedule_expression

}

resource "aws_cloudwatch_event_target" "ssosync" {
  rule      = aws_cloudwatch_event_rule.ssosync.name
  arn       = aws_lambda_function.ssosync.arn
}


resource "aws_lambda_permission" "allow_cloudwatch_execution" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ssosync.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssosync.arn
}
