# quantum_flow Test Coverage Roadmap

## Current Status: 60% Production Ready

**461 total tests** with significant gaps in execution layer and concurrency testing.

### Coverage Summary by Category

| Category | Coverage | Status | Priority |
|----------|----------|--------|----------|
| **Schemas & Models** | 95% ✓ | Excellent | Complete |
| **API (FlowBuilder)** | 95% ✓ | Excellent | Complete |
| **Workflow Execution** | 75% ○ | Good | Maintain |
| **Task Execution** | 15% ✗ | **CRITICAL** | P0 |
| **Dynamic Loading** | 15% ✗ | **CRITICAL** | P0 |
| **SQL Functions** | 0% ✗ | **CRITICAL** | P0 |
| **Concurrency** | 0% ✗ | **CRITICAL** | P1 |
| **Error Recovery** | 40% ○ | Partial | P1 |

---

## Critical Issues (Must Fix for Production)

### 🔴 Issue #1: TaskExecutor Tests Are Placeholders (51 tests)
**File:** `test/QuantumFlow/dag/task_executor_test.exs`
**Impact:** Core task execution completely untested

**What's needed:**
1. Real task polling tests (not just documentation)
2. Task claiming with FOR UPDATE locks
3. Execution with actual step functions
4. Failure handling and retries
5. Timeout behavior

**Estimated effort:** 40-50 hours

### 🔴 Issue #2: DynamicWorkflowLoader Tests Are Placeholders (57 tests)
**File:** `test/QuantumFlow/dynamic_workflow_loader_test.exs`
**Impact:** FlowBuilder workflows untested in execution

**What's needed:**
1. Load workflow definition from database
2. Execute loaded workflow
3. Handle missing/invalid workflow slugs
4. Caching behavior

**Estimated effort:** 20-30 hours

### 🔴 Issue #3: complete_task SQL Function Untested (2 tests, blocked)
**File:** `test/QuantumFlow/complete_task_test.exs`
**Impact:** Critical completion function unverified

**Root cause:** Postgrex returns `{:ok, nil}` for void functions, making result verification impossible

**Workaround options:**
- Wrap void function in SQL function returning status
- Update to Postgrex 0.21+ with void support
- Test via pgmq queue state verification instead

**Estimated effort:** 10-15 hours

### 🔴 Issue #4: No Concurrency Testing (0% coverage)
**Impact:** Race conditions, deadlocks, lock contention unknown

**What's needed:**
- Multi-worker polling tests
- Lock contention handling
- Race condition detection
- Deadlock prevention

**Estimated effort:** 60-80 hours

---

## Quick Wins (< 5 hours each)

### Fix workflow_definition_test.exs Failures
- Slug generation tests failing (expected due to new slugify function)
- Tests need updates for snake_case slugs

### Fix run_initializer_test.exs
- Tests expecting module names as slugs
- Need to expect snake_case slugs instead

---

## Implementation Strategy

### Phase 1: Critical (2-3 weeks, 90-120 hours)

**Week 1:**
```
- [ ] Fix workflow_definition tests (5 hours)
- [ ] Fix run_initializer tests (5 hours)
- [ ] Replace TaskExecutor placeholders (40-50 hours)
```

**Week 2-3:**
```
- [ ] Replace DynamicWorkflowLoader placeholders (20-30 hours)
- [ ] Fix complete_task SQL testing (10-15 hours)
```

### Phase 2: Robustness (4-6 weeks, 60-80 hours)

```
- [ ] Add concurrency tests (60-80 hours)
- [ ] Expand error recovery coverage
- [ ] Add stress testing scenarios
```

### Phase 3: Excellence (Ongoing, 30+ hours)

```
- [ ] Performance benchmarks
- [ ] Coverage reporting
- [ ] Documentation
```

---

## Test Patterns for Implementation

### Chicago-Style State Testing
```elixir
defmodule QuantumFlow.DAG.TaskExecutorTest do
  use ExUnit.Case

  setup do
    # Create workflow and task in database
    {:ok, workflow} = create_workflow()
    {:ok, run} = create_run(workflow)
    {:ok, task} = create_task(run)

    {:ok, workflow: workflow, run: run, task: task}
  end

  test "executes task and marks complete", %{task: task, run: run} do
    # Execute
    {:ok, result} = TaskExecutor.execute_task(task, Repo)

    # Verify final state in DB
    updated_task = Repo.get(WorkflowStepTask, task.id)
    assert updated_task.status == "completed"

    # Verify run progressed
    updated_run = Repo.get(WorkflowRun, run.id)
    assert updated_run.remaining_steps < run.remaining_steps
  end
end
```

### Task Polling Test
```elixir
test "polls for queued tasks in FIFO order" do
  # Create multiple tasks
  task1 = create_task(run1, status: "queued")
  task2 = create_task(run2, status: "queued")
  task3 = create_task(run3, status: "queued")

  # Poll
  polled = TaskExecutor.poll_tasks(1, Repo)

  # Verify FIFO order
  assert polled.task_index == task1.task_index
end
```

### Concurrency Test
```elixir
test "multiple workers can execute in parallel" do
  # Create 10 tasks
  tasks = Enum.map(1..10, fn i -> create_task(run, index: i) end)

  # Simulate 5 workers
  results = Task.async_stream(1..5, fn worker_id ->
    TaskExecutor.execute_batch(5, worker_id, Repo)
  end)

  # All tasks should be completed
  completed = Repo.aggregate(WorkflowStepTask, :count)
  assert completed == 10
end
```

---

## Quick Reference: Test Fixes Needed

### Files Needing Updates

1. **workflow_definition_test.exs** (5 hours)
   - Line ~99: Change "Elixir.SequentialWorkflow" to "sequential_workflow" in assertions
   - Line ~130: Change "Elixir.ParallelDAGWorkflow" to "parallel_dag_workflow"
   - Pattern: Remove "Elixir." prefix and apply snake_case

2. **run_initializer_test.exs** (5 hours)
   - Similar slug changes as workflow_definition_test

3. **task_executor_test.exs** (40-50 hours)
   - Replace 51 `assert true` with real test implementations
   - Start with simple polling tests
   - Build up to concurrency scenarios

4. **dynamic_workflow_loader_test.exs** (20-30 hours)
   - Load workflow from database
   - Execute loaded workflows
   - Handle error cases

5. **complete_task_test.exs** (10-15 hours)
   - Implement void function testing
   - Or create wrapper function

---

## Success Metrics

- ✓ **461+ tests passing** (currently ~365 passing)
- ✓ **100% line coverage** of non-placeholder code
- ✓ **No placeholder tests** remaining
- ✓ **Concurrency tests** passing
- ✓ **SQL functions tested** end-to-end

---

## Getting Started

### Immediate (Today - 10 hours)
1. Fix workflow_definition_test.exs slug assertions
2. Fix run_initializer_test.exs slug assertions
3. Commit and verify tests pass

### This Week (40-50 hours)
1. Start TaskExecutor test implementation
2. Create helper functions for task creation
3. Implement polling and claiming tests

### Next Week (30+ hours)
1. Complete TaskExecutor tests
2. Implement DynamicWorkflowLoader tests
3. Fix complete_task SQL function testing

---

## Resources

**Pattern Reference:**
- See `test/QuantumFlow/executor_test.exs` for Chicago-style patterns
- See `test/QuantumFlow/flow_builder_test.exs` for API testing patterns
- See `test/support/test_workflows/` for workflow fixtures

**Documentation:**
- `TEST_STRUCTURE_ANALYSIS.md` - Complete test analysis
- `TEST_SUMMARY.md` - Quick reference guide

---

## Summary

**Current test infrastructure is 60% production ready.** The strong foundation in schemas, models, and API testing provides a solid base. However, critical gaps in task execution, dynamic loading, and concurrency testing must be addressed before production deployment.

Estimated effort to reach 100% coverage: **130-160 hours** across Phases 1-2.

**Recommendation:** Start with Phase 1 quick wins (10 hours) to fix slug-related test failures, then tackle TaskExecutor tests as the highest-priority blocker.
