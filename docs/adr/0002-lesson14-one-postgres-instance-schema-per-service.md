---
status: accepted
---

# Lesson 14: one PostgreSQL instance, one schema per service

Textbook microservices give each service its own database instance. For a learning lab that is deployed and destroyed repeatedly, four RDS instances would quadruple the largest line of the bill. Lesson 14 runs one RDS PostgreSQL instance and gives User, Product, Order and Payment each their own PostgreSQL schema (`users`, `products`, `orders`, `payments`) with their own database role, so a service can only reach its own schema. Cart lives in DynamoDB (TTL, key-value access pattern) and Notification keeps no state.

## Considered options

- One instance per service: faithful to the pattern, roughly 4× the database cost, and four sets of credentials and security-group rules to manage.
- One instance, one shared schema: cheapest, but services could read each other's tables, which hides the ownership boundary the lesson is meant to teach.
- One instance, one schema and one role per service (chosen): the ownership boundary is enforced by database grants at a fraction of the cost. The docs state that production would split the instances along the same schema lines.

## Consequences

- The database is a shared failure domain: the "database fails in one AZ" scenario is answered by Multi-AZ on that single instance, not by isolation between services.
- Schema and role creation is a bootstrap step that must run before the services start.
