# Example: Real-Time Chat System

## Prompt

```
/design WhatsApp — 500M DAU, end-to-end encrypted, with group chats up to 1024 members
```

## What happens

1. **Clarify** — Message types (text, media, voice)? Read receipts? Offline delivery? Message retention?
2. **Estimate** — 500M DAU × 40 msgs/day = 20B msgs/day, ~230k msgs/sec, media storage ~5PB/year
3. **Propose** — Connection layer (WebSocket), message routing, media pipeline, encryption service
4. **Evaluate** — Fan-out on write vs read for groups, message ordering guarantees, storage tier
5. **Stress-test** — Group message storm (1024-member group), device failover, network partition
6. **Iterate** — "Add voice/video calling" → new real-time media pipeline

## Skills invoked

- `requirements-scoping` — availability, latency, encryption requirements
- `back-of-the-envelope` — message throughput, storage, bandwidth
- `service-decomposition` — connection, routing, media, presence services
- `messaging-streaming` — message delivery pipeline
- `data-storage` — message store, media metadata
- `blob-store` — media file storage
- `caching` — presence, session, recent messages
- `load-balancing` — WebSocket connection distribution
- `consistency-coordination` — message ordering in groups
- `resilience-failure` — offline message queue, retry semantics
