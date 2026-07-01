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
-- IF NOT EXISTS: prod/next build this by hand with CREATE INDEX CONCURRENTLY
-- (no write-lock on the live table) before this migration ships, so here it is a
-- no-op there; on fresh/dev/CI databases it builds the index.
CREATE INDEX IF NOT EXISTS indexed_events_group_canonical_time_idx ON indexed_events (
  project_id,
  environment_id,
  ((doc -> 'group' ->> 'id')),
  ((doc -> 'canonical_time')::text::bigint),
  id
);

ANALYZE indexed_events;
