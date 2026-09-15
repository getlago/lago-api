# frozen_string_literal: true

module Events
  module Stores
    module Utils
      class ClickhouseConnection
        MAX_RETRIES = 3
        MEMORY_ERROR_CODE = "MEMORY_LIMIT_EXCEEDED"
        PARSER_LIMIT_ERRORS = ["Max query size exceeded", "TOO_BIG_AST"].freeze

        RETRYABLE_ERRORS = [Errno::ECONNRESET, ActiveRecord::ActiveRecordError, NoMethodError, Net::ReadTimeout]

        # ClickHouse refuses to parse a statement larger than `max_query_size` or expanding to
        # more than `max_ast_elements` nodes. A charge carrying thousands of filters serializes
        # into a predicate past both defaults, so the query that hit one of them is replayed with
        # the limits raised. They travel as request parameters rather than in a `SETTINGS`
        # clause, as the parser needs the buffer size before it starts reading the statement.
        QUERY_SETTINGS = {max_query_size: 4_194_304, max_ast_elements: 500_000}.freeze

        def self.with_retry(&)
          with_parser_limit_retry do |settings|
            if settings.empty?
              yield
            else
              # Leasing the connection makes the settings apply to the relations built inside
              # the block, which would otherwise check out a connection of their own.
              ::Clickhouse::BaseRecord.with_connection do |connection|
                connection.with_settings(**settings) { yield }
              end
            end
          end
        end

        def self.connection_with_retry(&)
          with_parser_limit_retry do |settings|
            ::Clickhouse::BaseRecord.with_connection do |connection|
              if settings.empty?
                yield connection
              else
                connection.with_settings(**settings) { yield connection }
              end
            end
          end
        end

        # Queries run at the ClickHouse defaults. Only the one ClickHouse refused to parse is
        # replayed with the limits raised, and replaying it is what the retry would have done
        # anyway, identically and to no effect.
        def self.with_parser_limit_retry
          attempts = 0
          settings = {}

          begin
            attempts += 1

            yield settings
          rescue *RETRYABLE_ERRORS => e
            raise Events::Stores::Clickhouse::MemoryLimitError, e.message if memory_limit_error?(e)

            if settings.empty? && parser_limit_error?(e)
              settings = QUERY_SETTINGS
              retry
            end

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

        def self.parser_limit_error?(error)
          return false unless error.is_a?(ActiveRecord::ActiveRecordError)

          PARSER_LIMIT_ERRORS.any? { error.message.include?(it) }
        end
      end
    end
  end
end
