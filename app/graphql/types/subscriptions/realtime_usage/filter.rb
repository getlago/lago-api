# frozen_string_literal: true

module Types
  module Subscriptions
    module RealtimeUsage
      class Filter < Types::BaseObject
        graphql_name "HourlyUsageFilter"
        description "A charge filter with usage in the window, and its window totals"

        field :charge_filter_id, ID, null: true
        field :events_count, Integer, null: false
        field :invoice_display_name, String, null: true
        field :units, GraphQL::Types::Float, null: false
        field :values, Types::ChargeFilters::Values, null: false

        def invoice_display_name
          object.charge_filter&.display_name
        end

        def values
          object.charge_filter&.to_h || {}
        end
      end
    end
  end
end
