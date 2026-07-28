defmodule Singularity.Workflow.Repo.Migrations.ScheduleHtdagReaperCron do
  @moduledoc """
  Schedule HTDAG dual reapers via pg_cron when the extension is available.

  Jobs (ACE dual-reaper cadence, adapted):
  - htdag-rearm-stuck-started: every 2 minutes, grace_seconds=600
  - htdag-enqueue-orphaned-steps: every minute

  Fail-soft: if pg_cron cannot be created (non-superuser / missing package),
  the migration still succeeds; operators install pg_cron and re-run or apply
  engine/workflow/spine/sql/0002_reaper_cron.sql manually.
  """
  use Ecto.Migration

  def up do
    execute("""
    DO $body$
    BEGIN
      BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
      EXCEPTION
        WHEN insufficient_privilege THEN
          RAISE NOTICE 'pg_cron: insufficient privilege to CREATE EXTENSION; skip schedules';
          RETURN;
        WHEN undefined_file THEN
          RAISE NOTICE 'pg_cron: extension package missing; skip schedules';
          RETURN;
        WHEN OTHERS THEN
          RAISE NOTICE 'pg_cron: CREATE EXTENSION failed (%); skip schedules', SQLERRM;
          RETURN;
      END;

      IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        RAISE NOTICE 'pg_cron: extension not installed; skip schedules';
        RETURN;
      END IF;

      -- Idempotent: drop prior job names then reschedule.
      PERFORM cron.unschedule(j.jobid)
      FROM cron.job j
      WHERE j.jobname IN (
        'htdag-rearm-stuck-started',
        'htdag-enqueue-orphaned-steps'
      );

      PERFORM cron.schedule(
        'htdag-rearm-stuck-started',
        '*/2 * * * *',
        $cron$SELECT singularity_workflow.rearm_stuck_started_tasks(600)$cron$
      );

      PERFORM cron.schedule(
        'htdag-enqueue-orphaned-steps',
        '* * * * *',
        $cron$SELECT singularity_workflow.enqueue_orphaned_step_tasks()$cron$
      );
    END
    $body$;
    """)
  end

  def down do
    execute("""
    DO $body$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule(j.jobid)
        FROM cron.job j
        WHERE j.jobname IN (
          'htdag-rearm-stuck-started',
          'htdag-enqueue-orphaned-steps'
        );
      END IF;
    END
    $body$;
    """)
  end
end
