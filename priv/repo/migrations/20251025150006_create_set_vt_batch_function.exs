defmodule Pgflow.Repo.Migrations.CreateSetVtBatchFunction do
  @moduledoc """
  Creates pgflow.set_vt_batch() for batch visibility timeout updates.

  Matches pgflow's implementation - batch-update visibility timeouts for multiple
  messages in one operation. Used by start_tasks() to set task timeouts efficiently.

  Note: pgmq extension doesn't provide set_vt_batch natively, so pgflow implements it.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.set_vt_batch(
      queue_name TEXT,
      msg_ids BIGINT[],
      vt_offsets INTEGER[]
    )
    RETURNS SETOF PGMQ.MESSAGE_RECORD
    LANGUAGE plpgsql
    AS $$
    DECLARE
        qtable TEXT := pgmq.format_table_name(queue_name, 'q');
        sql    TEXT;
    BEGIN
        /* Safety checks */
        IF msg_ids IS NULL OR vt_offsets IS NULL OR array_length(msg_ids, 1) = 0 THEN
            RETURN;  -- nothing to do, return empty set
        END IF;

        IF array_length(msg_ids, 1) IS DISTINCT FROM array_length(vt_offsets, 1) THEN
            RAISE EXCEPTION
              'msg_ids length (%) must equal vt_offsets length (%)',
              array_length(msg_ids, 1), array_length(vt_offsets, 1);
        END IF;

        /* Dynamic UPDATE statement */
        /* One UPDATE joins with the unnested arrays */
        sql := format(
            $FMT$
            WITH input (msg_id, vt_offset) AS (
                SELECT  unnest($1)::bigint,
                        unnest($2)::int
            )
            UPDATE pgmq.%I q
            SET    vt      = clock_timestamp() + make_interval(secs => input.vt_offset),
                   read_ct = read_ct  -- no change, but keeps RETURNING list aligned
            FROM   input
            WHERE  q.msg_id = input.msg_id
            RETURNING q.msg_id,
                      q.read_ct,
                      q.enqueued_at,
                      q.vt,
                      q.message
            $FMT$,
            qtable
        );

        RETURN QUERY EXECUTE sql USING msg_ids, vt_offsets;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION pgflow.set_vt_batch(TEXT, BIGINT[], INTEGER[]) IS
    'Batch-update visibility timeouts for multiple pgmq messages. Matches pgflow implementation.'
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.set_vt_batch(TEXT, BIGINT[], INTEGER[])")
  end
end
