# Learning DevOps

Vocabulary shared by the lessons in this repository. Lesson 14 (e-commerce microservices on AWS) introduced the first terms; earlier lessons use only general infrastructure vocabulary.

## Language

### Shop (lesson 14)

**Customer**:
A person who has registered with the shop and can sign in. Identified by the identity provider's subject id.
_Avoid_: User (the service is named User Service, but the person is a Customer), account, client

**Product**:
An item the shop sells, with a catalogue price, a category and images.
_Avoid_: Item, SKU

**Cart**:
The set of products and quantities a signed-in Customer intends to buy. One per Customer; it expires if left untouched.
_Avoid_: Basket, shopping cart

**Order**:
A Customer's confirmed purchase: a snapshot of the Cart's items and prices at the moment of checkout, with a status that moves from pending payment to paid or payment failed.
_Avoid_: Purchase, transaction, checkout (checkout is the act that creates an Order)

**Payment**:
A single attempt to collect the money for one Order, with an outcome of succeeded or failed.
_Avoid_: Transaction, charge

**Notification**:
A message sent to a Customer about an Order event, such as "order received" or "payment failed".
_Avoid_: Email (the channel), alert (reserved for operators)

**Order event**:
A fact published when an Order changes, named in the past tense: `OrderCreated`, `PaymentSucceeded`, `PaymentFailed`. Services react to order events instead of calling each other.
_Avoid_: Message, command, webhook

### Platform (lesson 14)

**Service**:
One independently deployable unit of the shop (User, Product, Cart, Order, Payment, Notification). Each owns its data and talks to others only through the API or order events.
_Avoid_: Microservice (in prose), app, component

**Entry path**:
The route a browser request takes into the platform: CloudFront, then API Gateway, then the internal load balancer, then a service.
_Avoid_: Ingress, edge
