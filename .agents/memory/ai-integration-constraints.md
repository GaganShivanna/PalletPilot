# AI Integration Constraints

- No AI or video-processing pipeline exists yet; no constraints established.
- Record model, latency, cost, and on-device vs server limits here when the design lands.


- Real SAM / Muse Spark / Muse Image APIs unverified: no model IDs, endpoints, SDKs, or quotas confirmed. Adapters in `backend/app/providers/real.py` raise `ProviderUnavailable` with per-adapter handoff needs. Do not invent endpoints or claim integrations work without a real inference call.
- Mock segmentation assigns one track per pick and never merges on appearance; the real SAM adapter must associate detections across time with stable `track_id`s.
