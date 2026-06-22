# frozen_string_literal: true

module Events
  module Stores
    module Utils
      class ClickhouseConnection
        MAX_RETRIES = 3
        MEMORY_ERROR_CODE = "MEMORY_LIMIT_EXCEEDED"

        def self.with_retry(&)
          attempts = 0

          begin
            attempts += 1

            yield
          rescue Errno::ECONNRESET, ActiveRecord::ActiveRecordError, NoMethodError => e
            raise Events::Stores::Clickhouse::MemoryLimitError, e.message if memory_limit_error?(e)

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
          rescue Errno::ECONNRESET, ActiveRecord::ActiveRecordError, NoMethodError => e
            raise Events::Stores::Clickhouse::MemoryLimitError, e.message if memory_limit_error?(e)

            if attempts < MAX_RETRIES
              sleep(0.05)
              retry
            end
            raise
          end
        end

        def self.memory_limit_error?(error)
          return false unless error.is_a?(ActiveRecord::ActiveRecordError)

          error.message.include?(MEMORY_ERROR_CODE)
        end
      end
    end
  end
end
