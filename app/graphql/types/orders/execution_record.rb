# frozen_string_literal: true

module Types
  module Orders
    class ExecutionRecord < Types::BaseObject
      graphql_name "OrderExecutionRecord"

      field :errors, [String], null: false
      field :executed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :execution_mode, Types::Orders::ExecutionModeEnum, null: true
      field :invoice_id, ID, null: true

      def errors
        object["errors"] || []
      end
    end
  end
end
