# frozen_string_literal: true

module SolidusAdvancedPricing
  class Configuration
    # Largest payload PriceBatch will accept in one call. A synchronous request
    # has to stay inside the web timeout; anything bigger belongs in a job.
    attr_writer :batch_row_limit

    # Optional callable invoked by PriceBatch once every row is written and
    # before the transaction commits, receiving the batch. Raise from it to
    # abort. This is the seam for store policy -- "refuse a batch that moves
    # more than N% of prices by more than X%" -- which does not belong in a
    # general-purpose extension but does need somewhere to stand.
    attr_accessor :batch_guard

    def batch_row_limit
      @batch_row_limit ||= 500
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    alias_method :config, :configuration

    def configure
      yield configuration
    end
  end
end
