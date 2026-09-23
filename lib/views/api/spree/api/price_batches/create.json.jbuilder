json.mode @batch.mode
json.dry_run @batch.dry_run?
json.summary @batch.summary
json.results(@batch.results) do |result|
  json.merge! result.to_h
end
