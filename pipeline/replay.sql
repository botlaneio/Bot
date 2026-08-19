-- Replay captured fetches into the database.
--
-- `python -m pipeline.discover --emit boards.json` (or the same flag on
-- pipeline.poll) writes a JSON array of ingest payloads instead of sending
-- them. This is how those get applied without the poller holding credentials:
-- paste the array in place of the placeholder below and run it in the SQL
-- editor, or through the Supabase MCP connector.
--
-- Why this exists at all:
--
--   * It separates "did the fetch work" from "did the write work". When
--     something looks wrong, the captured payload is the exact evidence of
--     what the ATS actually returned that day.
--   * It lets a poll be run from a machine that has no service_role key —
--     which is how the very first poll happened, on 2026-08-18, before the key
--     was ever put on the dev box.
--
-- It is a fallback, not the normal path. The normal path is
-- .github/workflows/ingest.yml, which calls the same function over PostgREST.
--
-- Idempotent in the way that matters: replaying the same capture twice writes a
-- second poll_run that sees no changes. It does NOT close anything, because
-- every posting in the capture is seen again by the second run.

select payload->>'source'        as source,
       payload->>'board_token'   as board_token,
       public.ingest_ats_board(payload) as result
  from jsonb_array_elements($capture$
[]
$capture$::jsonb) as payload;
