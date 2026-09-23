# frozen_string_literal: true

module SolidusAdvancedPricing
  # Applies a PriceBatchRun's payload in committed slices.
  #
  # Slicing is the whole point and it costs two of the synchronous endpoint's
  # guarantees, deliberately:
  #
  # * The batch is no longer atomic. Each slice commits on its own, so a run that
  #   dies halfway leaves the slices before it applied. The status says `failed`
  #   and the report says how far it got, but nothing is rolled back.
  # * `batch_guard` sees the run so far rather than the finished picture, and is
  #   called once per slice. A guard that raises stops the run from that point;
  #   it cannot unmake the slices already committed.
  #
  # `replace` keeps its meaning: the deletion pass is deferred until every slice
  # has landed, so nothing is discarded that a later slice was about to re-create.
  # The cost there is a window, between the first slice and the last, in which
  # both the old and the new prices exist.
  # Inherits ActiveJob::Base rather than Spree::BaseJob: that class was added to
  # Solidus after 4.5 and is not in any released version, while this gem still
  # supports >= 4.5. The two behaviours it would have brought are repeated below.
  class PriceBatchJob < ActiveJob::Base
    # A slice writing many prices at once is a plausible deadlock victim.
    retry_on ActiveRecord::Deadlocked

    # Nothing to do if the run was deleted before the job reached it.
    discard_on ActiveJob::DeserializationError
    def perform(run_id)
      run = PriceBatchRun.find_by(id: run_id)
      return if run.nil? || run.status != "queued"

      run.update!(status: "running", started_at: Time.current, processed_rows: 0)

      results = apply_slices(run)
      results.concat(replacements_for(run)) if run.mode == "replace"

      run.record_report!(results)
      run.update!(status: "completed", finished_at: Time.current)
    rescue => error
      # The report is still written: a run that died at row 40,000 is exactly
      # the run whose first 40,000 outcomes someone needs to see.
      run&.record_report!(@results_so_far || [])
      run&.update(status: "failed", failure_reason: "#{error.class}: #{error.message}", finished_at: Time.current)
      raise
    end

    private

    def apply_slices(run)
      @results_so_far = []
      # One `seen` hash across every slice, so two rows naming the same price
      # are still caught when they land in different slices.
      seen = {}
      @touched = Hash.new { |hash, key| hash[key] = [] }

      run.rows.each_slice(SolidusAdvancedPricing.config.batch_slice_size).with_index do |slice, slice_index|
        offset = slice_index * SolidusAdvancedPricing.config.batch_slice_size

        batch = PriceBatch.new(
          rows: slice,
          mode: run.mode,
          dry_run: run.dry_run,
          row_limit: slice.size,
          seen: seen,
          replacements: false
        ).call

        @results_so_far.concat(reindex(batch.results, offset))
        batch.touched_ids.each { |key, ids| @touched[key].concat(ids) }

        run.update_columns(processed_rows: offset + slice.size, updated_at: Time.current)
      end

      @results_so_far
    end

    def replacements_for(run)
      PriceBatch.discard_untouched(@touched, dry_run: run.dry_run)
    end

    # Row indexes come back per slice; the caller only knows its own payload.
    def reindex(results, offset)
      results.map do |result|
        next result if result.index.nil?

        result.dup.tap { |copy| copy.index = result.index + offset }
      end
    end
  end
end
