---
status: accepted
---

# Lesson 14: one entry path — CloudFront → API Gateway → VPC Link → internal ALB

A public ALB alone would serve the six services with fewer parts. Lesson 14 instead puts every browser request through one CloudFront distribution (storefront from S3, `/api/*` to API Gateway), an API Gateway HTTP API that validates Cognito JWTs, a VPC Link, and an **internal** ALB that routes by path to the Fargate services in private subnets. The services therefore have no public address at all, the JWT is checked once at the edge of the VPC, WAF and rate limiting sit on the single CloudFront distribution, and the browser talks to one origin so there is no CORS.

## Considered options

- Public ALB only: cheapest and simplest, but the assignment names API Gateway, and authentication would have to live in every service.
- API Gateway in front of a public ALB: two public doors to the same services; nothing gained over the VPC Link.
- CloudFront → API Gateway → VPC Link → internal ALB (chosen).

## Consequences

- Service-to-service calls (Order → Cart) use the internal ALB too, and trust the `X-Customer-Sub` header only because nothing outside the VPC Link can reach the ALB.
- A VPC Link and an internal ALB add two components to the network diagram and a small fixed cost; this is accepted as the price of showing API Gateway and ALB each doing a distinct job.
