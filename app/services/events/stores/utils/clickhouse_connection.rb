# frozen_string_literal: true

module Events
  module Stores
    module Utils
      class ClickhouseConnection
        MAX_RETRIES = 3

        def self.with_retry(&)
          attempts = 0

          begin
            attempts += 1

            yield
          rescue Errno::ECONNRESET, ActiveRecord::ActiveRecordError, NoMethodError
            if attempts < MAX_RETRIES
              sleep(0.05)
              retry
            end

            raise
          end
        end

        def self.connection_with_retry(&)
          attempts = 0

          begin
            attempts += 1
            ::Clickhouse::BaseRecord.with_connection(&)
          rescue Errno::ECONNRESET, ActiveRecord::ActiveRecordError, NoMethodError
            if attempts < MAX_RETRIES
              sleep(0.05)
              retry
            end
            raise
          end
        end
      end
    end
  end
end
