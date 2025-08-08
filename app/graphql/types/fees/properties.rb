# frozen_string_literal: true

module Types
  module Fees
    class Properties < Types::BaseObject
      graphql_name "FeeProperties"

      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: true
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: true

      def from_datetime
        object.properties["from_datetime"]
      end

      def to_datetime
        object.properties["to_datetime"]
      end
    end
  end
end
