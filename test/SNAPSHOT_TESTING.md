# Snapshot Testing in QuantumFlow

## Overview

QuantumFlow uses **hybrid snapshot testing** to combine the benefits of:
- **Focused assertions** - Test critical business logic with explicit assertions
- **Snapshot regression detection** - Catch unintended structural changes

## When to Use Snapshots

Use snapshots for **complex outputs** with many fields/relationships:
- ✅ Full workflow/DAG structures with dependencies
- ✅ Complex orchestrator decomposition results
- ✅ Notification payloads with nested data
- ❌ Simple values (use direct assertions instead)
- ❌ Business logic that should be explicitly validated

## Usage Pattern

### Single Snapshot Assertion

```elixir
test "complex operation produces expected structure" do
  {:ok, result} = MyFunction.execute()

  # Focused assertions for critical behavior
  assert result.status == :success
  assert length(result.tasks) == 5

  # Snapshot for structure regression detection
  QuantumFlow.Test.Snapshot.assert_snapshot(result, "operation_structure")
end
```

### Updating Snapshots

When you intentionally change output structure:

```bash
# Update snapshots and re-run tests
SNAPSHOT_UPDATE=1 mix test
```

Or update a specific snapshot:
```bash
SNAPSHOT_UPDATE=1 mix test test/quantum_flow/orchestrator_test.exs
```

## File Organization

Snapshots are stored in `test/snapshots/` directory:

```
test/snapshots/
├── orchestrator_decompose_goal_linear.json
├── workflow_definition_parallel_dag.json
└── ...
```

## Git Integration

**Important**: Snapshots are committed to git (like Jest snapshots)

- ✅ Snapshot files are tracked
- ✅ Changes to snapshots appear in diffs
- ✅ Code review includes snapshot changes
- ❌ Snapshots are NOT ignored

## Best Practices

1. **Review snapshot diffs carefully** - They show exactly what changed
2. **Use with focused assertions** - Never replace all assertions with snapshots
3. **Update intentionally** - Only use SNAPSHOT_UPDATE when changes are intentional
4. **Keep snapshots readable** - Use pretty-printed JSON
5. **One snapshot per scenario** - Don't snapshot multiple cases in one test

## Example: Hybrid Testing Pattern

```elixir
test "orchestrator decomposes complex goal" do
  {:ok, task_graph} = Orchestrator.decompose_goal(complex_goal, decomposer)

  # What we care about: critical properties
  assert task_graph.root_tasks == [:analyze]
  assert map_size(task_graph.tasks) == 12
  assert task_graph.tasks[:finalize].depends_on == [:validate, :merge]

  # Structure regression detection: full snapshot
  QuantumFlow.Test.Snapshot.assert_snapshot(task_graph, "complex_goal_decomposition")
end
```

## Snapshot Format

Snapshots are stored as pretty-printed JSON for easy review:

```json
{
  "root_tasks": ["fetch"],
  "tasks": {
    "fetch": {
      "id": "fetch",
      "depends_on": [],
      "status": "pending"
    },
    "process": {
      "id": "process",
      "depends_on": ["fetch"],
      "status": "pending"
    }
  }
}
```

## Common Issues

### "Snapshot mismatch" Error

The output changed. Review the diff to determine:
- Is this an intentional change? → Run with `SNAPSHOT_UPDATE=1`
- Is this a bug? → Fix the code, don't update snapshots
- Is this a test data change? → Update test data

### Large Snapshots

If snapshots become too large:
- Extract sub-structures: Only snapshot the relevant part
- Use focused assertions instead
- Break into multiple smaller tests

## Helper Functions

### `assert_snapshot(data, snapshot_name, opts)`

Compare data with stored snapshot.

```elixir
# Create or compare snapshot
QuantumFlow.Test.Snapshot.assert_snapshot(result, "operation_result")

# Force update even if it matches
QuantumFlow.Test.Snapshot.assert_snapshot(result, "operation_result", update: true)
```

### `assert_json_equal(actual, expected, message)`

Compare two structures as JSON without snapshots.

```elixir
# Useful for dynamic comparisons
QuantumFlow.Test.Snapshot.assert_json_equal(actual_dag, expected_dag, "DAG structure")
```

## See Also

- [Testing Guide](./TESTING.md) - General testing patterns
- [Test Helper Modules](./support/) - Available test utilities
