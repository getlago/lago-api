# frozen_string_literal: true

module Types
  module Orders
    class ExecutionRecord < Types::BaseObject
      graphql_name "OrderExecutionRecord"

      field :errors, [String], null: false
      field :executed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :execution_mode, Types::Orders::ExecutionModeEnum, null: true
      field :invoice_id, ID, null: true

      field :applied_coupon_ids, [ID], null: false
      field :subscription_ids, [ID], null: false
      field :terminated_subscription_ids, [ID], null: false
      field :wallet_ids, [ID], null: false

      def errors
        object["errors"] || []
      end

      # Order types that create none of these, and records written before they existed, have no
      # such key at all.
      def applied_coupon_ids
        object["applied_coupon_ids"] || []
      end

      def subscription_ids
        object["subscription_ids"] || []
      end

      def terminated_subscription_ids
        object["terminated_subscription_ids"] || []
      end

      def wallet_ids
        object["wallet_ids"] || []
      end
    end
  end
end
