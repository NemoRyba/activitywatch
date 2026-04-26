# aw-agent-windows

`aw-agent-windows` is the endpoint-side fleet sync process for ActivityWatch.

V1 responsibilities:

- persist a stable endpoint `agent_id`
- maintain a durable sync outbox database
- handshake with the central `aw-server`
- upload queued `bucket_upsert` and `event_upsert` batches

The local bucket scan that fills the outbox is the next implementation slice.
