# Timeout Comparison: pgflow vs ex_pgflow

**Date:** 2025-10-25

---

## pgflow (TypeScript) Timeout Strategy

### 1. Per-Task Timeout (Database)
```sql
-- flows table
opt_timeout int not null default 60  -- 60 seconds per task

-- steps table
opt_timeout int  -- Can override flow default
```

**Purpose:** Task execution timeout (stored in DB)
**Default:** 60 seconds
**Usage:** How long a single task can execute before being considered failed

### 2. Visibility Timeout (Worker Config)
```typescript
// edge-worker/src/core/workerConfigTypes.ts
visibilityTimeout?: number  // default: 2 seconds
```

**Purpose:** pgmq message lock duration
**Default:** 2 seconds
**Usage:** How long a message is "invisible" to other workers after being read

### 3. Max Poll Seconds (Worker Config)
```typescript
maxPollSeconds?: number  // default: 5 seconds
```

**Purpose:** How long read_with_poll() waits for messages
**Default:** 5 seconds
**Usage:** Long-polling timeout for pgmq

### 4. NO Overall Workflow Timeout
**pgflow Edge Function runs indefinitely until workflow completes!**

---

## ex_pgflow (Elixir) Timeout Strategy (BEFORE)

### 1. Overall Execution Timeout (Client-Side)
```elixir
timeout = Keyword.get(opts, :timeout, 300_000)  # 5 minutes
```

**Purpose:** How long to poll for workflow completion
**Default:** 300 seconds (5 minutes)
**Usage:** Client stops polling after timeout, workflow continues in DB

### 2. NO Per-Task Timeout (Missing!)
We don't have `opt_timeout` in our migrations!

### 3. Visibility Timeout (Hardcoded)
```elixir
# task_executor.ex
vt = 30  # 30 seconds hardcoded
```

---

## What We're Missing vs pgflow

| Feature | pgflow | ex_pgflow | Status |
|---------|--------|-----------|--------|
| **Per-Task Timeout (DB)** | ✅ `opt_timeout` default 60s | ❌ Missing | ⚠️ Need to add |
| **Visibility Timeout** | ✅ Configurable, default 2s | ⚠️ Hardcoded 30s | ⚠️ Should make configurable |
| **Max Poll Seconds** | ✅ Configurable, default 5s | ⚠️ Hardcoded 5s | ⚠️ Should make configurable |
| **Overall Workflow Timeout** | ❌ None (runs forever) | ✅ 300s default | ⚠️ This is EXTRA (not in pgflow) |

---

## Recommended Changes

### Option 1: Match pgflow Exactly (Remove Overall Timeout)
```elixir
# Remove our overall execution timeout
# Just poll forever like pgflow Edge Function does

def execute_run(run_id, definition, repo, opts \\ []) do
  # No timeout parameter - just keep polling until complete
  poll_interval_ms = Keyword.get(opts, :poll_interval, 200)

  execute_loop(run_id, ...)  # Loops forever
end
```

**Pros:**
- ✅ Matches pgflow exactly
- ✅ Simpler code

**Cons:**
- ❌ Can hang forever if workflow never completes
- ❌ No way to stop polling from client

### Option 2: Keep Overall Timeout (Our Extra Feature)
```elixir
# Keep our overall timeout as an EXTRA feature
# pgflow doesn't have this, but it's useful!

def execute_run(run_id, definition, repo, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, :infinity)  # Allow :infinity
  # Rest stays the same
end
```

**Pros:**
- ✅ More control for users
- ✅ Prevents infinite polling
- ✅ Better for testing

**Cons:**
- ❌ Not in pgflow (but that's okay - it's an improvement!)

### Option 3: Hybrid (Add DB Timeout, Keep Client Timeout)
```elixir
# Add opt_timeout to migrations (matches pgflow)
# Keep our overall execution timeout (extra feature)

# Migration: Add opt_timeout columns
ALTER TABLE workflows ADD COLUMN opt_timeout INTEGER DEFAULT 60;
ALTER TABLE workflow_steps ADD COLUMN opt_timeout INTEGER;

# Use in start_tasks:
SELECT coalesce(step.opt_timeout, workflow.opt_timeout) + 2 AS vt_delay
```

**Pros:**
- ✅ Matches pgflow's per-task timeout
- ✅ Keeps our useful overall timeout
- ✅ Best of both worlds

**Cons:**
- ❌ More complexity

---

## Recommendation: **Option 3 (Hybrid)**

### Changes Needed

#### 1. Add Migration for opt_timeout
```elixir
# priv/repo/migrations/20251025170000_add_timeout_columns.exs
defmodule Pgflow.Repo.Migrations.AddTimeoutColumns do
  use Ecto.Migration

  def change do
    # Add opt_timeout to workflows table
    alter table(:workflows) do
      add :opt_timeout, :integer, default: 60, null: false
    end

    # Add opt_timeout to workflow_steps table
    alter table(:workflow_steps) do
      add :opt_timeout, :integer  # NULL means inherit from workflow
    end

    # Add constraint
    execute """
    ALTER TABLE workflows
    ADD CONSTRAINT opt_timeout_is_positive CHECK (opt_timeout > 0)
    """

    execute """
    ALTER TABLE workflow_steps
    ADD CONSTRAINT opt_timeout_is_positive CHECK (opt_timeout IS NULL OR opt_timeout > 0)
    """
  end
end
```

#### 2. Update start_tasks() to Use opt_timeout
```sql
-- In migration 20251025150010_update_start_tasks_with_worker_and_timeout.exs
-- Change hardcoded 32 to dynamic timeout

WITH timeouts AS (
  SELECT
    t.message_id,
    COALESCE(step.opt_timeout, flow.opt_timeout) + 2 AS vt_delay
  FROM workflow_step_tasks t
  JOIN workflows flow ON flow.workflow_slug = t.workflow_slug
  JOIN workflow_steps step ON step.workflow_slug = t.workflow_slug
                           AND step.step_slug = t.step_slug
  WHERE t.message_id = ANY(p_msg_ids)
)
PERFORM pgflow.set_vt_batch(
  p_workflow_slug,
  array_agg(t.message_id),
  array_agg(t.vt_delay)  -- Use dynamic timeout!
)
FROM timeouts t
```

#### 3. Make Visibility Timeout Configurable
```elixir
# task_executor.ex
def execute_run(run_id, definition, repo, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, :infinity)  # Overall timeout (our extra!)
  poll_interval_ms = Keyword.get(opts, :poll_interval, 200)
  batch_size = Keyword.get(opts, :batch_size, 10)
  max_poll_seconds = Keyword.get(opts, :max_poll_seconds, 5)  # NEW
  visibility_timeout = Keyword.get(opts, :visibility_timeout, 30)  # NEW (from DB)
  # ...
end
```

---

## Summary: pgflow Defaults vs Our Defaults

| Setting | pgflow Default | ex_pgflow Current | ex_pgflow Recommended |
|---------|---------------|-------------------|----------------------|
| **Per-Task Timeout** | 60s (DB) | ❌ None | 60s (DB) ✅ |
| **Visibility Timeout** | 2s (config) | 30s (hardcoded) | 30s (configurable) |
| **Max Poll Seconds** | 5s (config) | 5s (hardcoded) | 5s (configurable) |
| **Overall Timeout** | ∞ (none) | 300s (5 min) | ∞ (configurable) |
| **Poll Interval** | N/A | 200ms | 200ms ✅ |
| **Batch Size** | 10 (config) | 10 (hardcoded) | 10 (configurable) |

---

## Conclusion

**YES, we should add opt_timeout to match pgflow!**

**Changes:**
1. ✅ Add `opt_timeout` column to workflows (default 60)
2. ✅ Add `opt_timeout` column to workflow_steps (nullable)
3. ✅ Update start_tasks() to use dynamic timeouts
4. ✅ Make worker settings configurable (visibility_timeout, max_poll_seconds, batch_size)
5. ⚠️ Keep our overall execution timeout (set default to :infinity to match pgflow behavior)

**Our overall timeout is a FEATURE, not a bug:**
- pgflow Edge Functions run in Supabase (serverless, auto-managed)
- ex_pgflow runs in user's app (might want control over polling duration)
- Configurable timeout = best of both worlds!
