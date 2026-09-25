# frozen_string_literal: true

module Types
  module Fees
    class Properties < Types::BaseObject
      graphql_name "FeeProperties"

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      def from_datetime
        period_boundary(:from_date, "from_datetime")
      end

      def to_datetime
        period_boundary(:to_date, "to_datetime")
      end

      private

      def period_boundary(boundary, property)
        if context[:preserve_add_on_fee_period_dates] && object.add_on?
          object.properties[property]&.to_date
        else
          object.date_boundaries[boundary]
        end
      end
    end
  end
end
