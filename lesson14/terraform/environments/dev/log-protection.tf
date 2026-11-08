# CloudWatch Logs data protection: masks personal data as ****** for anyone reading these log groups. Readers with
# logs:Unmask can still reveal the original. Only events ingested after the policy exists are masked.
locals {
  protected_log_groups = merge(
    { for s, m in module.service : s => m.log_group_name },
    {
      db-init    = module.db_init.log_group_name
      api-access = module.api.access_log_group_name
    },
  )

  # The Cognito sub every service logs on each request ("customer_sub":"<uuid>"). The regex anchors on the key so
  # request_id and event_id, also UUIDs, stay readable; "..." stands for the ":" that CDI regexes may not contain.
  log_custom_identifiers = [
    { Name = "CustomerSub", Regex = "customer_sub...[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" },
  ]

  log_data_identifiers = [
    "arn:aws:dataprotection::aws:data-identifier/EmailAddress", # customer emails (notification log mode)
    "arn:aws:dataprotection::aws:data-identifier/IpAddress",    # client IP in the API access log
    "CustomerSub",
  ]
}

resource "aws_cloudwatch_log_data_protection_policy" "this" {
  for_each = local.protected_log_groups

  log_group_name = each.value
  policy_document = jsonencode({
    Name          = "${local.name}-${each.key}-mask-pii"
    Version       = "2021-06-01"
    Configuration = { CustomDataIdentifier = local.log_custom_identifiers }
    Statement = [
      {
        # Required by the policy syntax; no findings destination, so no audit report is written anywhere.
        Sid            = "audit"
        DataIdentifier = local.log_data_identifiers
        Operation      = { Audit = { FindingsDestination = {} } }
      },
      {
        Sid            = "mask"
        DataIdentifier = local.log_data_identifiers
        Operation      = { Deidentify = { MaskConfig = {} } }
      },
    ]
  })
}
