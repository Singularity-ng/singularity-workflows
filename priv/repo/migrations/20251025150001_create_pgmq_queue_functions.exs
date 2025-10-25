defmodule Pgflow.Repo.Migrations.CreatePgmqQueueFunctions do
  use Ecto.Migration

  def up do
    # Create read_with_poll function (backport from pgmq 1.5.0)
    # This matches pgflow's implementation for task polling
    execute("""
    CREATE FUNCTION pgflow.read_with_poll(
      queue_name TEXT,
      vt INTEGER,
      qty INTEGER,
      max_poll_seconds INTEGER DEFAULT 5,
      poll_interval_ms INTEGER DEFAULT 100,
      conditional JSONB DEFAULT '{}'
    )
    RETURNS SETOF PGMQ.MESSAGE_RECORD
    SET search_path = ''
    AS $$
    DECLARE
        r pgmq.message_record;
        stop_at TIMESTAMP;
        sql TEXT;
        qtable TEXT := pgmq.format_table_name(queue_name, 'q');
    BEGIN
        stop_at := clock_timestamp() + make_interval(secs => max_poll_seconds);
        LOOP
          IF (SELECT clock_timestamp() >= stop_at) THEN
            RETURN;
          END IF;

          sql := FORMAT(
              $QUERY$
              WITH cte AS
              (
                  SELECT msg_id
                  FROM pgmq.%I
                  WHERE vt <= clock_timestamp() AND CASE
                      WHEN %L != '{}'::jsonb THEN (message @> %2$L)::integer
                      ELSE 1
                  END = 1
                  ORDER BY msg_id ASC
                  LIMIT $1
                  FOR UPDATE SKIP LOCKED
              )
              UPDATE pgmq.%I m
              SET
                  vt = clock_timestamp() + %L,
                  read_ct = read_ct + 1
              FROM cte
              WHERE m.msg_id = cte.msg_id
              RETURNING m.msg_id, m.read_ct, m.enqueued_at, m.vt, m.message;
              $QUERY$,
              qtable, conditional, qtable, make_interval(secs => vt)
          );

          FOR r IN
            EXECUTE sql USING qty
          LOOP
            RETURN NEXT r;
          END LOOP;
          IF FOUND THEN
            RETURN;
          ELSE
            PERFORM pg_sleep(poll_interval_ms::numeric / 1000);
          END IF;
        END LOOP;
    END;
    $$ LANGUAGE plpgsql;
    """)

    # Create function to initialize workflow queue
    execute("""
    CREATE FUNCTION pgflow.ensure_workflow_queue(workflow_slug TEXT)
    RETURNS TEXT
    LANGUAGE SQL
    SET search_path TO ''
    AS $$
      SELECT pgmq.create(workflow_slug)
      WHERE NOT EXISTS (
        SELECT 1 FROM pgmq.list_queues() WHERE queue_name = workflow_slug
      );
      SELECT workflow_slug;
    $$;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS pgflow.read_with_poll")
    execute("DROP FUNCTION IF EXISTS pgflow.ensure_workflow_queue")
  end
end
