defmodule Pgflow.Repo.Migrations.SimplifyEnsureWorkflowQueue do
  @moduledoc """
  Simplifies ensure_workflow_queue to avoid the ambiguous column issue with pgmq.list_queues().
  
  Instead of checking if the queue exists before creating, we use pgmq.create() which
  is idempotent (returns existing queue name if already exists).
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION pgflow.ensure_workflow_queue(workflow_slug TEXT)
    RETURNS TEXT
    LANGUAGE SQL
    SET search_path TO ''
    AS $$
      SELECT pgmq.create(workflow_slug);
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
        SELECT 1 FROM pgmq.list_queues() q WHERE q.queue_name = workflow_slug
      );
      SELECT workflow_slug;
    $$;
    """)
  end
end
