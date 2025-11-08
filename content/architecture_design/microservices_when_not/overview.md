# When NOT to Microservice

## What It Is

Microservices split an application into independent services with separate databases, deployed and scaled individually. The monolith-first principle recommends starting with a single codebase and extracting services only when organizational or scaling needs demand it. A modular monolith structures code into isolated modules (domains) within one application, giving many benefits of microservices without distributed system complexity.

## Why It Matters

Microservices add latency, distributed transactions, deployment complexity, and debugging overhead. A 10-person team splitting a 6-month-old app into 20 services spends months on orchestration, monitoring, and network failures instead of shipping features. Monoliths with clear module boundaries scale further than premature microservices with tangled dependencies. Microservices solve specific problems (team independence, independent scaling); applying them without those problems wastes time.

## When to Use

- Independent teams need to deploy without coordinating (50+ engineers, multiple product lines)
- Specific components require different scaling (background jobs, real-time feeds)
- Different technology stacks are necessary (Python for ML, Go for high-throughput APIs)
- Compliance requires data isolation (PCI-DSS for payment data, GDPR for EU customers)
- After a modular monolith proves domain boundaries are stable

## Three Common Pitfalls

1. **Splitting before validating domain boundaries:** Microservices lock in boundaries. If domains shift (User service needs Order data), refactoring requires cross-service changes, database migrations, and contract updates. Start with a modular monolith to validate boundaries cheaply.

2. **Ignoring distributed system costs:** Microservices introduce network failures, eventual consistency, distributed tracing, and service discovery. A monolith handles these concerns with database transactions and stack traces. Don't pay distributed system costs without distributed system benefits.

3. **Premature extraction for "best practices":** Extracting services because "it's how big companies do it" ignores that big companies have big-company problems (hundreds of engineers, polyglot needs). A 5-person team doesn't have those problems yet.

---

## Monolith First Principle

Start with a monolith. Extract services when scaling or organizational needs justify the cost.

**Signs you need microservices:**
- Teams block each other on deployments
- One component (e.g., image processing) requires 10x more resources than others
- Hiring requires different tech stacks (ML in Python, core app in Rails)

**Signs you don't:**
- Team is under 20 engineers
- App deploys successfully multiple times per day
- No component requires vastly different scaling

Monoliths deploy faster, debug easier, and refactor cheaper. Extract services only when monolith constraints become painful.

## Modular Monolith Alternative

A modular monolith structures code into isolated modules (domains) with clear boundaries but shares one database and deployment.

```ruby
# app/domains/orders/
#   models/
#     order.rb
#   services/
#     checkout_order.rb
#   controllers/
#     orders_controller.rb

# app/domains/inventory/
#   models/
#     product.rb
#   services/
#     reserve_stock.rb

# Orders module calls Inventory via service interface
class CheckoutOrder
  def call
    result = Inventory::ReserveStock.call(product_id: context.product_id)
    context.fail!(error: "Out of stock") unless result.success?
    # ...
  end
end
```

Modules communicate through service objects, not direct model access. Benefits: domain isolation, easier extraction later. Costs: discipline required to enforce boundaries.

## When Microservices Help

Microservices solve organizational and scaling problems, not code quality problems.

**Independent Teams:** 3 product teams ship features without coordinating deploys. Each team owns a service.

**Independent Scaling:** Image processing service needs 50 workers; web API needs 5 servers. Scaling them together wastes resources.

**Polyglot Requirements:** ML models run in Python; real-time feed in Go; core app in Rails. Language boundaries map to service boundaries.

## When Microservices Hurt

**Shared Data:** If Services A and B both read/write User data, they're not independent. Splitting forces distributed transactions or eventual consistency, complicating logic that was simple in a monolith.

**Distributed Transactions:** Charging a credit card and updating order status must succeed or fail together. Microservices require sagas (multi-step compensating transactions) instead of database rollbacks.

**Debugging Complexity:** A 500 error in a monolith has a stack trace. In microservices, trace the request across 5 services using distributed tracing tools like Jaeger.

## Message Queues (Exposure Only)

Microservices communicate asynchronously via message queues (Kafka, RabbitMQ) to decouple services.

```ruby
# orders-service publishes event
OrderCreatedPublisher.publish(order_id: order.id, user_id: order.user_id)

# inventory-service consumes event
class OrderCreatedConsumer
  def process(event)
    Inventory::ReserveStock.call(order_id: event[:order_id])
  end
end
```

Message queues enable eventual consistency but complicate debugging (messages lost, duplicate processing, ordering issues). Use only when async processing or decoupling justifies the complexity.

## Distributed Transactions Example

A monolith handles order checkout in a single transaction:

```ruby
Order.transaction do
  order.update!(status: "paid")
  PaymentGateway.charge(order.total)
  Inventory.decrement(order.product_id, order.quantity)
end
```

If any step fails, the database rolls back. In microservices:

```ruby
# orders-service
result = PaymentService.charge(order.total)
if result.success?
  InventoryService.decrement(order.product_id, order.quantity)
else
  # Compensate: what if inventory already decremented?
end
```

Microservices require saga patterns (event-driven compensation) to handle failures, adding complexity.

## Signs You Prematurely Extracted Services

- Deploying requires coordinating 5+ service releases
- Database queries join data across service boundaries via API calls
- Adding a feature touches 3+ services
- Engineers spend more time debugging network issues than business logic
- "Distributed monolith": services share a database or deploy together

Recombine services or adopt a modular monolith.

---

## Trade-offs Box

- **Advantage:** Monoliths simplify deployment, debugging, and refactoring; modular monoliths provide domain boundaries without distributed costs.
- **Cost:** Monoliths eventually hit organizational or scaling limits; refactoring into services later requires careful boundary extraction.
- **When to skip:** Skip microservices if team is under 20 engineers, app deploys multiple times daily, and no component requires vastly different scaling.

---

## Debugging Checklist

When microservices cause pain, check:

1. Team size: If under 20 engineers, reconsider whether services add value
2. Deployment frequency: If services must deploy together, they're a distributed monolith
3. Shared data: If services share a database or frequently call each other's APIs, boundaries are wrong
4. Network failures: If debugging involves tracing requests across 5+ services, evaluate consolidation
5. Transaction complexity: If compensating sagas replace simple database rollbacks, consider a monolith
6. Module boundaries: If a modular monolith enforces boundaries equally well, delay extraction

---

## One-Minute Recap

- Monolith-first principle: start with one codebase, extract services only when organizational or scaling needs justify distributed costs
- Modular monoliths provide domain isolation without network, transaction, or debugging complexity
- Microservices help when teams need independent deploys, components need independent scaling, or polyglot stacks are required
- Microservices hurt when data is shared, transactions span services, or debugging becomes tracing network calls
- Signs of premature extraction: coordinated deploys, cross-service joins, engineers debugging orchestration instead of features
