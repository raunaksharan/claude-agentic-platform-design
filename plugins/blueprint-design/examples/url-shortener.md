# Example: URL Shortener

## Prompt

```
/design a URL shortener that handles 10k writes/sec and billions of reads
```

## What happens

The orchestrator runs the GUIDE loop:

1. **Clarify** — Pins down: custom aliases? analytics? TTL? geo-distribution?
2. **Estimate** — Back-of-the-envelope: 10k writes/sec × 86400 = ~864M URLs/day, read:write ratio ~100:1, storage growth ~500GB/year
3. **Propose** — Pulls in skills: `data-storage`, `caching`, `load-balancing`, `sequencer`, `dns`
4. **Evaluate** — Trade-offs: hash vs counter ID, cache-aside vs write-through, SQL vs KV store
5. **Stress-test** — Hot key (viral link), cache stampede, region failover
6. **Iterate** — "What if we need analytics per click?" → adds `messaging-streaming` + `distributed-logging`

## Skills invoked

- `requirements-scoping` — NFRs (latency p99, availability SLA)
- `back-of-the-envelope` — capacity math
- `sequencer` — short-code generation
- `data-storage` — primary store selection
- `caching` — read path optimization
- `load-balancing` — traffic distribution
- `dns` — custom domain resolution
- `content-delivery` — edge redirect caching
