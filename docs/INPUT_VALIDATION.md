# Input Validation for Dynamic Workflows

singularity_workflow ensures **all inputs are validated** before creating dynamic workflows, preventing invalid data from reaching the database.

## Validation Strategy

### 1. Client-Side Validation (Elixir)
Validates inputs **before** database calls to provide fast, helpful error messages.

### 2. Database-Level Validation (PostgreSQL)
Enforces constraints with `CHECK` constraints and SQL functions as a second layer of defense.

## Client-Side Validation

### Workflow Slug Validation

```elixir
validate_workflow_slug(slug)
```

**Rules:**
- ✅ Must be a string
- ✅ Cannot be empty
- ✅ Max length: 255 characters
- ✅ Format: `^[a-zA-Z_][a-zA-Z0-9_]*$` (alphanumeric + underscore, must start with letter/underscore)

**Examples:**
```elixir
# Valid
validate_workflow_slug("my_workflow")        # => :ok
validate_workflow_slug("EmailCampaign2024")  # => :ok

# Invalid
validate_workflow_slug("")                   # => {:error, :workflow_slug_cannot_be_empty}
validate_workflow_slug("123invalid")         # => {:error, :workflow_slug_invalid_format}
validate_workflow_slug("has-dashes")         # => {:error, :workflow_slug_invalid_format}
```

### Step Slug Validation

```elixir
validate_step_slug(slug)
```

**Rules:**
- ✅ Same as workflow_slug validation
- ✅ Prevents SQL injection
- ✅ Ensures valid identifier for PostgreSQL

### Step Type Validation

```elixir
validate_step_type(opts)
```

**Rules:**
- ✅ Must be `"single"` or `"map"`
- ✅ Defaults to `"single"` if not provided

**Examples:**
```elixir
# Valid
validate_step_type(step_type: "single")  # => :ok
validate_step_type(step_type: "map")     # => :ok
validate_step_type([])                   # => :ok (defaults to "single")

# Invalid
validate_step_type(step_type: "batch")   # => {:error, :step_type_must_be_single_or_map}
```

### Initial Tasks Validation

```elixir
validate_initial_tasks(opts)
```

**Rules:**
- ✅ Must be a positive integer (> 0)
- ✅ Only applies to "map" steps
- ✅ `nil` is valid (determined at runtime)

**Examples:**
```elixir
# Valid
validate_initial_tasks(initial_tasks: 100)   # => :ok
validate_initial_tasks([])                   # => :ok (nil)

# Invalid
validate_initial_tasks(initial_tasks: 0)     # => {:error, :initial_tasks_must_be_positive}
validate_initial_tasks(initial_tasks: -5)    # => {:error, :initial_tasks_must_be_positive}
validate_initial_tasks(initial_tasks: "10")  # => {:error, :initial_tasks_must_be_integer}
```

### Max Attempts Validation

```elixir
validate_max_attempts(opts)
```

**Rules:**
- ✅ Must be a non-negative integer (≥ 0)
- ✅ Defaults to 3 if not provided
- ✅ 0 = no retries (fail immediately)

**Examples:**
```elixir
# Valid
validate_max_attempts(max_attempts: 5)    # => :ok
validate_max_attempts(max_attempts: 0)    # => :ok (no retries)
validate_max_attempts([])                 # => :ok (defaults to 3)

# Invalid
validate_max_attempts(max_attempts: -1)   # => {:error, :max_attempts_must_be_non_negative}
```

### Timeout Validation

```elixir
validate_timeout(opts)
```

**Rules:**
- ✅ Must be a positive integer (> 0)
- ✅ Defaults to 60 seconds if not provided
- ✅ Measured in seconds

**Examples:**
```elixir
# Valid
validate_timeout(timeout: 120)      # => :ok (2 minutes)
validate_timeout(timeout: 3600)     # => :ok (1 hour)
validate_timeout([])                # => :ok (defaults to 60)

# Invalid
validate_timeout(timeout: 0)        # => {:error, :timeout_must_be_positive}
validate_timeout(timeout: -10)      # => {:error, :timeout_must_be_positive}
```

## Usage Example

### Safe Dynamic Workflow Creation

```elixir
alias Singularity.Workflow.FlowBuilder

# All validation happens automatically
case FlowBuilder.create_flow("ai_workflow", repo, timeout: 120) do
  {:ok, workflow} ->
    IO.puts("Workflow created!")

  {:error, :workflow_slug_cannot_be_empty} ->
    IO.puts("Error: Provide a workflow slug")

  {:error, :timeout_must_be_positive} ->
    IO.puts("Error: Timeout must be > 0")

  {:error, reason} ->
    IO.inspect(reason, label: "Unexpected error")
end
```

### Adding Steps with Validation

```elixir
# This will FAIL validation
FlowBuilder.add_step("my_workflow", "", [], repo)
# => {:error, :step_slug_cannot_be_empty}

# This will FAIL validation
FlowBuilder.add_step("my_workflow", "process", [], repo, step_type: "batch")
# => {:error, :step_type_must_be_single_or_map}

# This will SUCCEED
FlowBuilder.add_step("my_workflow", "process", [], repo,
  step_type: "map",
  initial_tasks: 100,
  timeout: 300
)
# => {:ok, %{"step_slug" => "process", ...}}
```

## Database-Level Validation

Even if client validation is bypassed, PostgreSQL enforces:

### 1. Slug Validation (`is_valid_slug` function)
```sql
CREATE FUNCTION Singularity.Workflow.is_valid_slug(slug TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN slug ~ '^[a-zA-Z_][a-zA-Z0-9_]*$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

### 2. Check Constraints
```sql
-- Workflows table
ALTER TABLE workflows
ADD CONSTRAINT workflow_slug_is_valid CHECK (Singularity.Workflow.is_valid_slug(workflow_slug));

-- Steps table
ALTER TABLE workflow_steps
ADD CONSTRAINT step_slug_is_valid CHECK (Singularity.Workflow.is_valid_slug(step_slug));

-- Timeout must be positive
ALTER TABLE workflows
ADD CONSTRAINT timeout_is_positive CHECK (timeout > 0);
```

### 3. Type Constraints
```sql
-- Step type enum validation
ALTER TABLE workflow_steps
ADD CONSTRAINT step_type_is_valid CHECK (step_type IN ('single', 'map'));
```

## Error Handling

All validation errors return descriptive atoms:

| Error Atom | Meaning | Fix |
|-----------|---------|-----|
| `:workflow_slug_cannot_be_empty` | Empty string provided | Provide a slug |
| `:workflow_slug_too_long` | > 255 characters | Shorten the slug |
| `:workflow_slug_invalid_format` | Contains invalid characters | Use only `a-zA-Z0-9_` |
| `:workflow_slug_must_be_string` | Wrong type | Pass a string |
| `:step_type_must_be_single_or_map` | Invalid step type | Use "single" or "map" |
| `:initial_tasks_must_be_positive` | ≤ 0 | Provide positive integer |
| `:timeout_must_be_positive` | ≤ 0 | Provide timeout > 0 |
| `:max_attempts_must_be_non_negative` | < 0 | Use 0 or positive integer |

## Testing Validation

```elixir
defmodule FlowBuilderTest do
  use ExUnit.Case

  test "rejects empty workflow slug" do
    assert {:error, :workflow_slug_cannot_be_empty} =
      FlowBuilder.create_flow("", repo)
  end

  test "rejects invalid timeout" do
    assert {:error, :timeout_must_be_positive} =
      FlowBuilder.create_flow("my_workflow", repo, timeout: 0)
  end

  test "accepts valid workflow" do
    assert {:ok, %{"workflow_slug" => "my_workflow"}} =
      FlowBuilder.create_flow("my_workflow", repo, timeout: 120)
  end
end
```

## Benefits

✅ **Fail Fast** - Invalid inputs caught before database calls  
✅ **Clear Errors** - Descriptive error atoms for debugging  
✅ **Type Safety** - Guards ensure correct types  
✅ **Defense in Depth** - Client + database validation  
✅ **SQL Injection Prevention** - Slug format validation  
✅ **AI/LLM Safety** - Validate AI-generated workflows  

## AI/LLM Integration

When AI generates workflows dynamically, validation ensures:

1. **Slug format** - AI can't generate invalid identifiers
2. **Timeout bounds** - AI can't create infinite timeouts
3. **Step types** - AI limited to "single" or "map"
4. **Initial tasks** - AI can't create 0 or negative task counts

**Example:**
```elixir
# AI-generated workflow (unsafe input)
ai_generated_slug = "my-workflow-123"  # Invalid!

# Validation catches it
case FlowBuilder.create_flow(ai_generated_slug, repo) do
  {:error, :workflow_slug_invalid_format} ->
    # Sanitize AI input
    safe_slug = String.replace(ai_generated_slug, "-", "_")
    FlowBuilder.create_flow(safe_slug, repo)
end
```

---

**Summary:** singularity_workflow validates **all** dynamic workflow inputs at both the client (Elixir) and database (PostgreSQL) layers, ensuring data integrity and preventing SQL injection.
