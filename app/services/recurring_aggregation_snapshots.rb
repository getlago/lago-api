# frozen_string_literal: true

module RecurringAggregationSnapshots
  FORCED_READ_KEY = :lago_recurring_aggregation_snapshots_forced_read

  class << self
    # Forces the snapshot read on (true) or off (false) for the duration of the block. Reserved for
    # the parity comparison, which runs both paths on one organization; production callers never
    # force it.
    def with_forced_read(enabled)
      raise "RecurringAggregationSnapshots read already forced" unless Thread.current[FORCED_READ_KEY].nil?

      Thread.current[FORCED_READ_KEY] = enabled
      begin
        yield
      ensure
        Thread.current[FORCED_READ_KEY] = nil
      end
    end

    def read_enabled?
      Thread.current[FORCED_READ_KEY] != false
    end
  end
end
