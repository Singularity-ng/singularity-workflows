defmodule Singularity.Workflow.Repo.Migrations.FixSetVtBatchMessageRecordShape do
  @moduledoc """
  Align set_vt_batch RETURNING with current pgmq.message_record.

  pgmq.message_record gained `last_read_at` and `headers`. The prior RETURNING
  list omitted them, so set_vt_batch raised a type mismatch and aborted
  start_tasks mid-claim (tasks stuck queued; execute_dynamic hung).

  Consumer: public.start_tasks (04401 fence) + TaskExecutor / C21 lease path.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION singularity_workflow.set_vt_batch(
      queue_name TEXT,
      msg_ids BIGINT[],
      vt_offsets INTEGER[]
    )
    RETURNS SETOF pgmq.message_record
    LANGUAGE plpgsql
    AS $$
    DECLARE
        qtable TEXT := pgmq.format_table_name(queue_name, 'q');
        sql    TEXT;
    BEGIN
        IF msg_ids IS NULL OR vt_offsets IS NULL OR array_length(msg_ids, 1) = 0 THEN
            RETURN;
        END IF;

        IF array_length(msg_ids, 1) IS DISTINCT FROM array_length(vt_offsets, 1) THEN
            RAISE EXCEPTION
              'msg_ids length (%) must equal vt_offsets length (%)',
              array_length(msg_ids, 1), array_length(vt_offsets, 1);
        END IF;

        sql := format(
            $FMT$
            WITH input (msg_id, vt_offset) AS (
                SELECT  unnest($1)::bigint,
                        unnest($2)::int
            )
            UPDATE pgmq.%I q
            SET    vt = clock_timestamp() + make_interval(secs => input.vt_offset)
            FROM   input
            WHERE  q.msg_id = input.msg_id
            RETURNING q.msg_id,
                      q.read_ct,
                      q.enqueued_at,
                      q.last_read_at,
                      q.vt,
                      q.message,
                      q.headers
            $FMT$,
            qtable
        );

        RETURN QUERY EXECUTE sql USING msg_ids, vt_offsets;
    END;
    $$;
    """)

    execute("""
    COMMENT ON FUNCTION singularity_workflow.set_vt_batch(TEXT, BIGINT[], INTEGER[]) IS
    'Batch-update pgmq VT; RETURNING matches pgmq.message_record (incl. last_read_at, headers).';
    """)
  end

  def down do
    # Prior broken shape intentionally not restored.
    execute("DROP FUNCTION IF EXISTS singularity_workflow.set_vt_batch(TEXT, BIGINT[], INTEGER[])")
  end
end
