json.call(@run, :id, :status, :mode, :dry_run, :total_rows, :processed_rows, :started_at, :finished_at)
json.failure_reason @run.failure_reason if @run.failure_reason.present?

if @run.finished?
  json.summary @run.summary
  json.results @run.reported_results
  json.results_truncated @run.results_truncated?
end
