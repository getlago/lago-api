# frozen_string_literal: true

module Types
  module Orders
    class Object < Types::BaseObject
      graphql_name "Order"

      field :id, ID, null: false
      field :number, String, null: false
      field :status, Types::Orders::StatusEnum, null: false
      field :order_type, Types::Orders::OrderTypeEnum, null: false
      field :execution_mode, Types::Orders::ExecutionModeEnum, null: true
      field :backdated_billing, Types::Orders::BackdatedBillingEnum, null: true

      field :billing_snapshot, GraphQL::Types::JSON, null: false
      field :currency, String, null: true
      field :execution_record, GraphQL::Types::JSON, null: true
      field :executed_at, GraphQL::Types::ISO8601DateTime, null: true

      field :customer, Types::Customers::Object, null: false
      field :order_form, Types::OrderForms::Object, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
