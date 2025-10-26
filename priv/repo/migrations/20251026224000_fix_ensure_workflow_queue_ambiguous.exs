defmodule Pgflow.Repo.Migrations.FixEnsureWorkflowQueueAmbiguous do
  @moduledoc """
  Fixes the ensure_workflow_queue function by qualifying the queue_name column reference.
  
  The issue was that pgmq.list_queues() returns columns including queue_name, and the
  WHERE clause comparing queue_name = workflow_slug (the parameter) caused ambiguity.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.ensure_workflow_queue(workflow_slug TEXT)
    RETURNS TEXT
    LANGUAGE SQL
    SET search_path TO ''
    AS $$
      SELECT pgmq.create(workflow_slug)
      WHERE NOT EXISTS (
        SELECT 1 FROM pgmq.list_queues() q WHERE q.queue_name = workflow_slug
      );
      SELECT workflow_slug;
    $$;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.ensure_workflow_queue(workflow_slug TEXT)
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
end
