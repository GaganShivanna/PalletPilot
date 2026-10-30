# AI Integration Constraints

- Integration (2026-10-30, `integration/backend-ai`): hosted SAM (`sam-3.1`, `POST {MUSE_BASE_URL}/responses`) and Muse Spark (`muse-spark-1.3`, `POST {MUSE_BASE_URL}/chat/completions`) wired via `AI_PROVIDER`; no local weights. SAM API transport verified (job `084e388b…`, 3 completed responses, zero matches — kept as valid completed result per backend owner; no zero-detection failure policy). Detection accuracy + Muse Spark real inference unverified; "trash can" smoke test planned in `docs/AI_INTEGRATION.md`, paid runs need approval.
- Smoke test PASSED 2026-10-30 (job `78bf4cbc…`): 1 SAM call → 1 track → 1 Spark ID ("Black Mesh Wastebasket") → 1 SQLite row → CSV row; 39 s wall.
- Muse Image unimplemented (`ProviderUnavailable`); per-item photo fallback covers it.
- SAM limits: even frame dims, uniform dims, encoded clip ≤ 20 MB, 1–5 `SAM_CONCEPTS`; no cross-concept dedup; external calls sequential (`PROVIDER_MAX_CONCURRENCY` unenforced).
- Muse Spark conditions mapped conservatively in `real.py::map_muse_spark_condition` (`new_sealed→new`, all others→`unknown` + raw preserved in `review_reasons`); never upgrade open_box/used into graded claims.
- Mock segmentation assigns one track per pick and never merges on appearance; SAM associates within one response via `concept_<i>_<object_id>` track IDs (occlusion/re-entry splits unresolved).
