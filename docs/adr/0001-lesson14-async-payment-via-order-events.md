---
status: accepted
---

# Lesson 14: payment is asynchronous, driven by order events

Checkout in lesson 14 could call Payment Service synchronously inside `POST /orders`, which is simpler to read and gives the customer an immediate answer. We chose the asynchronous shape instead: Order Service stores the Order as `PENDING_PAYMENT`, publishes `OrderCreated` to an SNS topic, and Payment and Notification each consume their own SQS queue; Payment publishes `PaymentSucceeded`/`PaymentFailed`, which Order Service consumes to finish the Order and Notification consumes to email the customer. The customer polls `GET /orders/{id}` for the outcome.

## Considered options

- Synchronous payment inside `POST /orders`: fewer moving parts, but an outage in Payment or Notification fails checkout, which defeats the assignment's resilience scenarios ("one service is down, the others keep working"; "order created but email service is failing").
- Asynchronous via SNS → SQS fan-out (chosen): each consumer has its own queue and dead-letter queue, so a down service only delays its own work.

## Consequences

- Order status is eventually consistent; the storefront and the curl walkthrough must poll.
- Every consumer must be idempotent (events can be delivered more than once).
- Two more AWS services (SNS, SQS) and their IAM policies appear in the Terraform modules.
