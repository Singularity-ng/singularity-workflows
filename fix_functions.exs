#!/usr/bin/env elixir

{:ok, conn} = Postgrex.start_link(
  hostname: "localhost",
  port: 5432,
  username: System.get_env("USER") || "mhugo",
  password: "",
  database: "ex_pgflow"
)

# Fix create_flow function
create_flow_sql = """
CREATE OR REPLACE FUNCTION pgflow.create_flow(
  p_workflow_slug TEXT,
  p_max_attempts INTEGER DEFAULT 3,
  p_timeout INTEGER DEFAULT 60
)
RETURNS TABLE (
  workflow_slug TEXT,
  max_attempts INTEGER,
  timeout INTEGER,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SET search_path = 'public'
AS $$
BEGIN
  IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
    RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
  END IF;
  INSERT INTO workflows (workflow_slug, max_attempts, timeout)
  VALUES (p_workflow_slug, p_max_attempts, p_timeout)
  ON CONFLICT (workflow_slug) DO UPDATE
  SET workflow_slug = workflows.workflow_slug;
  PERFORM pgflow.ensure_workflow_queue(p_workflow_slug);
  RETURN QUERY
  SELECT w.workflow_slug, w.max_attempts, w.timeout, w.created_at
  FROM workflows w
  WHERE w.workflow_slug = p_workflow_slug;
END;
$$;
"""

Postgrex.query!(conn, create_flow_sql, [])
IO.puts("Fixed create_flow function")

# Fix add_step function
add_step_sql = """
CREATE OR REPLACE FUNCTION pgflow.add_step(
  p_workflow_slug TEXT,
  p_step_slug TEXT,
  p_depends_on TEXT[] DEFAULT '{}',
  p_step_type TEXT DEFAULT 'single',
  p_initial_tasks INTEGER DEFAULT NULL,
  p_max_attempts INTEGER DEFAULT NULL,
  p_timeout INTEGER DEFAULT NULL
)
RETURNS TABLE (
  workflow_slug TEXT,
  step_slug TEXT,
  step_type TEXT,
  step_index INTEGER,
  depends_on TEXT[],
  initial_tasks INTEGER,
  max_attempts INTEGER,
  timeout INTEGER,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SET search_path = 'public'
AS $$
DECLARE
  v_next_index INTEGER;
  v_deps_count INTEGER;
BEGIN
  IF NOT pgflow.is_valid_slug(p_workflow_slug) THEN
    RAISE EXCEPTION 'Invalid workflow_slug: %', p_workflow_slug;
  END IF;
  
  IF NOT pgflow.is_valid_slug(p_step_slug) THEN
    RAISE EXCEPTION 'Invalid step_slug: %', p_step_slug;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM workflows WHERE workflow_slug = p_workflow_slug) THEN
    RAISE EXCEPTION 'Workflow "%" does not exist. Call create_flow() first.', p_workflow_slug;
  END IF;

  IF EXISTS (SELECT 1 FROM workflow_steps WHERE workflow_slug = p_workflow_slug AND step_slug = p_step_slug) THEN
    RAISE EXCEPTION 'Step "%" already exists in workflow "%"', p_step_slug, p_workflow_slug;
  END IF;

  SELECT COALESCE(MAX(step_index), 0) + 1
  INTO v_next_index
  FROM workflow_steps
  WHERE workflow_slug = p_workflow_slug;

  SELECT array_length(p_depends_on, 1)
  INTO v_deps_count;

  INSERT INTO workflow_steps (
    workflow_slug, step_slug, step_index, depends_on, step_type,
    initial_tasks, max_attempts, timeout
  )
  VALUES (
    p_workflow_slug, p_step_slug, v_next_index, p_depends_on, p_step_type,
    p_initial_tasks, p_max_attempts, p_timeout
  );

  INSERT INTO workflow_step_dependencies (workflow_slug, step_slug, depends_on_step)
  SELECT p_workflow_slug, p_step_slug, unnest(p_depends_on);

  RETURN QUERY
  SELECT 
    ws.workflow_slug, ws.step_slug, ws.step_type, ws.step_index,
    ws.depends_on, ws.initial_tasks, ws.max_attempts, ws.timeout, ws.created_at
  FROM workflow_steps ws
  WHERE ws.workflow_slug = p_workflow_slug AND ws.step_slug = p_step_slug;
END;
$$;
"""

Postgrex.query!(conn, add_step_sql, [])
IO.puts("Fixed add_step function")

Process.exit(conn, :normal)
