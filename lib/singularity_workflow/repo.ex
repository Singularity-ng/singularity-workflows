defmodule Singularity.Workflow.Repo do
  use Ecto.Repo,
    otp_app: :singularity_workflow,
    adapter: Ecto.Adapters.Postgres
end
