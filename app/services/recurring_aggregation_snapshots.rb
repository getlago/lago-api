# frozen_string_literal: true

module RecurringAggregationSnapshots
  FORCED_READ_KEY = :lago_recurring_aggregation_snapshots_forced_read

  class << self
    # Forces the snapshot read on (true) or off (false) for the duration of the block, whatever the
    # feature flag says. Reserved for the parity comparison, which runs both paths on one
    # organization; production callers never force it.
    def with_forced_read(enabled)
      raise "RecurringAggregationSnapshots read already forced" unless Thread.current[FORCED_READ_KEY].nil?

      Thread.current[FORCED_READ_KEY] = enabled
      begin
        yield
      ensure
        Thread.current[FORCED_READ_KEY] = nil
      end
    end

    def read_enabled?(organization)
      forced = Thread.current[FORCED_READ_KEY]
      return forced unless forced.nil?

      organization.feature_flag_enabled?(:persisted_recurring_values)
    end
  end
end
