# Mocked AWS: no credentials or real resources.
mock_provider "aws" {}

variables {
  name = "lesson14-dev"
}

run "insights_enabled" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "lesson14-dev" && output.cluster_name == "lesson14-dev"
    error_message = "The cluster must use name as-is."
  }
  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "Container Insights must be enabled by default."
  }
  assert {
    condition     = aws_ecs_cluster_capacity_providers.this.capacity_providers == toset(["FARGATE", "FARGATE_SPOT"])
    error_message = "The cluster must offer FARGATE and FARGATE_SPOT."
  }
  assert {
    condition = (
      one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).capacity_provider == "FARGATE" &&
      one(aws_ecs_cluster_capacity_providers.this.default_capacity_provider_strategy).weight == 1
    )
    error_message = "The default strategy must be FARGATE with weight 1."
  }
}

run "insights_disabled" {
  command = plan
  variables {
    container_insights = false
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "disabled"
    error_message = "container_insights = false must disable Container Insights."
  }
}
