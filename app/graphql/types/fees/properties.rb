# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Fees
    class Properties < Types::BaseObject
      graphql_name "FeeProperties"

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      def from_datetime
        object.date_boundaries[:from_date]
      end

      def to_datetime
        object.date_boundaries[:to_date]
      end
    end
  end
end
