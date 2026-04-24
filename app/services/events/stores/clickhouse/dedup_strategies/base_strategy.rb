# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      module DedupStrategies
        class BaseStrategy
          DEDUPLICATED_COLUMNS = %w[value decimal_value properties precise_total_amount_cents].freeze

          SELECT_COLUMNS = %w[
            code
            organization_id
            external_subscription_id
            transaction_id
            timestamp
            value
            decimal_value
            properties
            precise_total_amount_cents
          ].freeze

          GROUP_COLUMNS = %w[
            code
            organization_id
            external_subscription_id
            transaction_id
            timestamp
          ].freeze

          def initialize(subscription:, boundaries:, code:)
            @subscription = subscription
            @boundaries = boundaries
            @code = code
          end

          def name
            raise NotImplementedError
          end

          def sql
            raise NotImplementedError
          end

          private

          attr_reader :subscription, :boundaries, :code

          def from_datetime
            boundaries[:from_datetime]
          end

          def to_datetime
            boundaries[:to_datetime]
          end

          def organization_id
            subscription.organization_id
          end

          def external_subscription_id
            subscription.external_id
          end

          def sanitized_key_filters(alias_prefix: nil)
            prefix = alias_prefix ? "#{alias_prefix}." : ""
            ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                "#{prefix}organization_id = ? " \
                "AND #{prefix}code = ? " \
                "AND #{prefix}external_subscription_id = ? " \
                "AND #{prefix}timestamp BETWEEN ? AND ?",
                organization_id,
                code,
                external_subscription_id,
                from_datetime,
                to_datetime
              ]
            )
          end
        end
      end
    end
  end
end
