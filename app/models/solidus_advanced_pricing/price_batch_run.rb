# frozen_string_literal: true

module SolidusAdvancedPricing
  # A submitted batch and what became of it. Exists so a client can hand over a
  # payload too large to apply inside a request and ask about it afterwards.
  #
  # `::Spree::Base` is qualified from the root: the
  # `solidus_advanced_pricing/spree` decorator namespace shadows the bare
  # `Spree` constant here otherwise (Zeitwerk const-shadowing gotcha).
  class PriceBatchRun < ::Spree::Base
    self.table_name = "solidus_advanced_pricing_price_batch_runs"

    STATUSES = %w[queued running completed failed].freeze

    # Reporting every outcome for a payload this size would store megabytes
    # nobody reads. Counts cover the rest; these are the rows you act on.
    REPORTED_STATUSES = %i[error deleted].freeze
    REPORTED_LIMIT = 1_000

    belongs_to :user, class_name: ::Spree::UserClassHandle.new, optional: true

    validates :status, inclusion: {in: STATUSES}
    validates :mode, inclusion: {in: SolidusAdvancedPricing::PriceBatch::MODES}

    scope :recent, -> { order(created_at: :desc) }

    # Payload and report are JSON in a text column rather than a serialized
    # attribute: `serialize`'s coder argument changed shape across the Rails
    # versions this gem supports, and one explicit pair of accessors outlives
    # that.
    def rows
      @rows ||= payload.present? ? JSON.parse(payload) : []
    end

    def rows=(value)
      @rows = value
      self.payload = JSON.generate(value || [])
      self.total_rows = Array(value).size
    end

    def report_hash
      report.present? ? JSON.parse(report) : {}
    end

    def summary = report_hash["summary"] || {}

    def reported_results = report_hash["results"] || []

    def results_truncated? = report_hash["results_truncated"] == true

    def record_report!(results)
      counts = results.group_by(&:status).transform_values(&:size).transform_keys(&:to_s)
      notable = results.select { |result| REPORTED_STATUSES.include?(result.status) }

      self.report = JSON.generate(
        summary: counts,
        results: notable.first(REPORTED_LIMIT).map(&:to_h),
        results_truncated: notable.size > REPORTED_LIMIT
      )
    end

    def finished? = %w[completed failed].include?(status)
  end
end
