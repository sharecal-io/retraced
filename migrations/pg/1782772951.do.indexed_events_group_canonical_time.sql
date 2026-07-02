-- Composite btree for org-scoped audit-log queries (LEV-2813).
--
-- An org export orders by canonical_time but filters by group. With only the
-- single-column canonical_time_idx + GIN group_id_idx, Postgres walks
-- canonical_time newest->oldest across EVERY tenant and discards non-matching
-- rows to fill a page (measured: 583s / ~1M rows discarded for one page on a
-- dormant org). This composite lets it seek straight to the tenant's slice and
-- read it already ordered by (canonical_time, id) -- no cross-tenant scan, no sort.
--
-- The btree is only used as an Index Cond when the group is filtered by
-- EQUALITY (doc -> 'group' ->> 'id' = $); that is why getFilters() switched the
-- group scope filter from the GIN @> operator to =. The GIN @> operator cannot
-- use this index.
--
-- This migration will NOT build the index non-concurrently on a populated
-- indexed_events -- that would take a lock blocking audit-log ingestion for the
-- whole build. Instead:
--   * index already present (prod/next, built by hand with CREATE INDEX
--     CONCURRENTLY per the runbook) -> no-op.
--   * table populated but index missing (DR restore / fresh prod-sized DB /
--     dropped-and-re-migrated) -> RAISE, failing the deploy loudly so an
--     operator runs the CONCURRENTLY step, rather than silently locking writes.
--   * empty table (dev / CI / local) -> build inline; nothing to lock.
DO $$
BEGIN
  IF to_regclass('indexed_events_group_canonical_time_idx') IS NOT NULL THEN
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM indexed_events LIMIT 1) THEN
    RAISE EXCEPTION 'indexed_events is populated but indexed_events_group_canonical_time_idx is missing. Build it manually with CREATE INDEX CONCURRENTLY (see LEV-2813 runbook), then re-run migrate. Refusing to build non-concurrently on a populated table (it would lock out ingestion for the whole build).';
  END IF;

  CREATE INDEX indexed_events_group_canonical_time_idx ON indexed_events (
    project_id,
    environment_id,
    ((doc -> 'group' ->> 'id')),
    ((doc -> 'canonical_time')::text::bigint),
    id
  );
END
$$;

ANALYZE indexed_events;
