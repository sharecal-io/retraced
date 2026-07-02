-- Do NOT drop this index while the `=` group filter (1.13.3+) is deployed:
-- `=` with no index is slower than the original GIN `@>`, so dropping it here
-- re-introduces the slow path. Roll the code back to `@>` (1.13.2) first, then
-- drop. CONCURRENTLY is safe (and avoids the ACCESS EXCLUSIVE lock that plain
-- DROP queues writes behind) because this file is a single statement, so
-- postgrator runs it outside a transaction.
DROP INDEX CONCURRENTLY IF EXISTS indexed_events_group_canonical_time_idx;
