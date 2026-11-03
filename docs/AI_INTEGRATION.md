# PalletPilot — AI Integration

How the FastAPI backend (`AI_PROVIDER`) selects between offline mock
providers and the real hosted AI adapters (SAM segmentation + Muse Spark
identification). No local model weights are used anywhere.

Verification status (2026-10-30): **hosted SAM API communication is
verified** — job `084e388b…` completed 3 `POST {MUSE_BASE_URL}/responses`
round-trips with `status=completed` responses (all three matched nothing
for concepts `headphones,keyboard,speaker`, so zero items were produced;
zero detections is a valid completed result). **End-to-end real AI is
verified** — smoke job `78bf4cbc…` (`SAM_CONCEPTS="trash can"`) produced
1 SAM track → 1 Muse Spark identification ("Black Mesh Wastebasket") →
1 persisted item → CSV row (see "Smoke test" verdict). Detection accuracy
beyond this single case is owned by the AI engineer and remains untuned.

## Provider sets (`AI_PROVIDER`)

| Value | Segmentation | Identification | Photos |
|---|---|---|---|
| `mock` (default) | `MockSegmentationProvider` | `MockIdentificationProvider` | `MockPhotoProvider` (always fallback) |
| `sam` | `SamSegmentationProvider` | mock | mock |
| `muse_spark` | mock | `MuseSparkIdentificationProvider` | mock |
| `muse_image` | mock | mock | `MuseImagePhotoProvider` (raises; fallback covers) |
| `real` | SAM | Muse Spark | Muse Image (raises; fallback covers) |

Selection lives in `backend/app/providers/factory.py`. Unknown names raise
`ProviderUnavailable` — the backend never silently substitutes mock output
for a real provider. Mock output is always labeled (`provider="mock"`,
`needs_review=true`, `Demo draft` marker) and must never be presented as
verified listings.

## Required configuration

Secrets live in gitignored `backend/.env` (template: `backend/.env.example`),
read via `backend/app/config.py` only.

| Variable | Required for | Default |
|---|---|---|
| `MUSE_API_KEY` | `sam`, `muse_spark`, `real` | (none — raises `ProviderUnavailable` when blank) |
| `SAM_CONCEPTS` | `sam`, `real` — 1–5 comma-separated product types, e.g. `box,bottle,electronics` | (none — raises `ProviderUnavailable` when blank) |
| `MUSE_BASE_URL` | hosted endpoint base | `https://api.meta.ai/v1` |
| `MUSE_SPARK_MODEL` | identification model | `muse-spark-1.3` |
| `SAM_MODEL` | segmentation model | `sam-3.1` |
| `SAM_TIMEOUT_S` | SAM request timeout | `180` |
| `PROVIDER_TIMEOUT_S` | Muse Spark request timeout | `60` |
| `PROVIDER_MAX_RETRIES` | transient-error retries (identification) | `2` |

Python dependency for SAM output parsing: `meta-sam-parser==0.1.0` in
`backend/requirements.txt`. It is imported lazily (inside
`SamSegmentationProvider.detect`), so mock mode runs without it; calling
SAM without it raises `ProviderUnavailable` with install instructions.

## Execution flow

`POST /jobs` → `app/services/pipeline.py::run_pipeline`:

1. **Sample frames** — OpenCV, `SAMPLE_FPS` (2–5), cap `MAX_FRAMES`, JPEGs
   under `<job_dir>/frames/`.
2. **Segment** — `providers.segmentation.detect(frames, <job_dir>/masks/)`.
   - Mock: evenly spaced frames become `item_0…`, no masks.
   - SAM (`app/providers/sam_api.py`): re-encodes frames to mp4
     (`sam_input.mp4`, preserving frame order/indices), then one
     `POST {MUSE_BASE_URL}/responses` per concept with the clip inlined as
     base64 (`mask_encoding="one_bit"`). Raw output text is saved as
     `sam_response_<i>.txt`; `sam_output.py` parses boxes+masks via
     `meta_sam_parser`; `sam_products.py` picks the sharpest-masked
     observation per track and writes `<track>_crop.jpg` + `<track>_mask.png`.
     IDs look like `concept_0_7` (`concept_<index>_<sam_object_id>`).
3. **Identify** — one call per product; transient `ProviderError`s retried
   per `PROVIDER_MAX_RETRIES`, permanent failures degrade to an
   `Unidentified item (...)` reviewable draft (never a pipeline abort).
   - Muse Spark (`real.py`): `POST {MUSE_BASE_URL}/chat/completions` with
     the product image as an `image_url` data-URI and a strict
     `json_schema` (`_ProductIdentity`: name/brand/category/condition/
     confidence/review_reasons). Model conditions are mapped onto the
     public resale schema (below); the raw observation is preserved in
     `review_reasons`.
4. **Photos** — `MuseImagePhotoProvider` raises `ProviderUnavailable`;
   `product_photos.py` catches it per item and copies the representative
   image (SAM crop or source frame) into `<job_dir>/photos/`.
5. **Listings/pricing/persist** — unchanged Phase 2 logic: deterministic
   drafts, fixture pricing (`mock_fixture` or unpriced — real product
   names have no fixture rows, so real items are unpriced and excluded
   from revenue), SQLite persistence, CSV export.

## Condition mapping (Muse Spark → public schema)

The public contract (`Item`, `PATCH /items/{id}`) allows only
`new | like_new | good | fair | poor | parts | unknown`. The mapping in
`real.py::map_muse_spark_condition` is deliberately conservative — it never
upgrades an observation into a graded claim:

| Muse Spark | Stored | Rationale |
|---|---|---|
| `new_sealed` | `new` | Sealed item is new; safe equivalent. |
| `open_box` | `unknown` | Opened box says nothing about grade; `like_new` would overstate. |
| `used` | `unknown` | Un graded use; `good`/`fair` would invent a grade. |
| `damaged` | `unknown` | Damage severity ungraded; seller must assess. |
| `unknown` | `unknown` | Passthrough. |

Whenever the stored value differs from the raw observation, a
`review_reasons` entry records it, e.g.
`Observed condition (Muse Spark): open_box; recorded as 'unknown' pending
seller review.` Unit tests cover every mapping
(`tests/test_muse_spark.py::test_condition_mapping_is_conservative`).

## Expected outputs (real providers)

- Items: one per SAM track (`<job_id>:concept_<i>_<obj>`), `provider` =
  `muse_spark` (identification stage), `needs_review=true`, representative
  crop as `original_image_url`, mask file alongside the crop.
- Listing drafts without the `Demo draft` marker (mock-only), with
  seller-confirmation review reasons.
- Photos: original-crop fallback copies (Muse Image unimplemented).
- Financials: estimates; real items unpriced until a pricing source exists.
- CSV: same columns/shape as mock mode.
- Failures: missing key/concepts → job `failed` with a clear message at the
  SEGMENTING stage; per-item identification/photo errors → reviewable
  drafts; transient HTTP errors (408/429/5xx, timeouts, connect errors)
  retried then degraded per item.

## Limitations

- SAM requires even frame width/height, uniform frame dims, and an encoded
  clip ≤ 20 MB — long videos fail fast with `ProviderError` (job-level).
- No dedup across SAM concepts: the same physical item found under two
  concepts becomes two items (flagged in `review_reasons`); occlusion/
  re-entry splits are likewise not resolved.
- External calls run sequentially; `PROVIDER_MAX_CONCURRENCY` is not yet
  enforced (slow but safe).
- `services/segmentation.py::detect_items` is a dead Phase 1 stub; the
  pipeline uses the provider interface, not it.
- Muse Image generation is unimplemented; all photos are fallbacks.

## Running

Mock mode (fully offline):

```bash
cd backend
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest -q
AI_PROVIDER=mock .venv/bin/uvicorn app.main:app
```

## Smoke test: "trash can" (PASSED 2026-10-30, job `78bf4cbc…`)

Result: 1 SAM call (~19 s) → 1 track (`concept_0_0`) → 1 Spark call
(~19 s, "Black Mesh Wastebasket", conf 0.85) → 1 SQLite row
(`provider=muse_spark`, `needs_review=1`) → CSV header + 1 row.
39 s wall. One expected handled error (Muse Image fallback).
Artefacts kept under `backend/data/jobs/78bf4cbc…/`.

Original plan (kept for repeat runs — spends credits, needs approval):

Goal: validate SAM mask/crop generation and the SAM→Muse Spark handoff on
the existing liquidation video (`backend/data/jobs/084e388b…/video.mp4`,
~20 s, trash can clearly visible in later frames). Detection wording is
NOT a pass criterion — accuracy is owned by the AI engineer.

Setup (settings load at server start, so restart after editing `.env`):

```bash
cd backend
# in .env: AI_PROVIDER=real, SAM_CONCEPTS="trash can", MUSE_API_KEY set
.venv/bin/uvicorn app.main:app
```

Steps:

```bash
# 1. Create a pallet
curl -X POST http://127.0.0.1:8000/pallets \
  -H 'Content-Type: application/json' \
  -d '{"name":"smoke-trash-can","purchase_cost":0,"additional_costs":0}'
# → note the pallet id

# 2. Upload the existing clip, linked to the pallet
curl -X POST http://127.0.0.1:8000/jobs \
  -F video=@data/jobs/084e388b03374583a6836b20ec04406a/video.mp4 \
  -F pallet_id=<pallet_id>
# → note the job id

# 3. Poll until completed/failed (~30–60 s; calls run sequentially)
curl http://127.0.0.1:8000/jobs/<job_id>

# 4. Inspect artifacts and records
ls data/jobs/<job_id>/masks/            # sam_response_0.txt, concept_0_*_crop.jpg/_mask.png
.venv/bin/python -c "
import sqlite3
con = sqlite3.connect('data/meta.db')
for r in con.execute(\"SELECT id, title, condition, provider, needs_review FROM items WHERE job_id='<job_id>'\"): print(r)"
curl http://127.0.0.1:8000/pallets/<pallet_id>/items
curl http://127.0.0.1:8000/pallets/<pallet_id>/export
```

Expected outputs:

- Job `completed`, `frame_count` 62.
- `masks/sam_response_0.txt` non-empty (`<Nf>` records with box+mask data).
- ≥1 `concept_0_*_crop.jpg` + `concept_0_*_mask.png` pair; crop shows the
  trash can; mask is a white-on-black silhouette.
- ≥1 SQLite item with `provider=muse_spark`, plausible title, condition in
  the resale set, `needs_review=1`, review reasons citing the concept.
- `photos/` fallback copies; CSV has header + ≥1 row; financials show
  unpriced items excluded from revenue.

Verdict rules:

- **Pass:** ≥1 mask+crop pair + ≥1 persisted Spark identification + CSV rows.
- **Inconclusive (not an adapter bug):** completed with zero items again —
  the concept didn't match; report back before trying alternate nouns
  (`trash bin`, `wastebasket`), each retry spends credits.
- **Fail (adapter bug):** job `failed` with a parse/traceback error on
  non-empty SAM output; missing crop/mask files despite a non-empty
  response; Spark error mishandling; listings present but missing from
  SQLite.

Mixed modes (`AI_PROVIDER=sam` or `muse_spark`) are useful for isolating
one adapter while keeping the other stages on mock.
