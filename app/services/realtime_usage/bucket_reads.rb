# frozen_string_literal: true

module RealtimeUsage
  # The ClickHouse helpers every read of the usage buckets shares.
  module BucketReads
    private

    def quote(value)
      Clickhouse::UsageBucket.connection.quote(value)
    end

    def quote_list(values)
      values.map { |value| quote(value) }.join(", ")
    end

    def with_retry(&)
      Events::Stores::Utils::ClickhouseConnection.with_retry(&)
    end
  end
end
