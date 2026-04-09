# frozen_string_literal: true

module Types
  module Quotes
    class CreateInput < BaseInputObject
      graphql_name "CreateQuoteInput"

      argument :customer_id, ID, required: true

      argument :auto_execute, Boolean, required: false
      argument :backdated_billing, Types::Orders::BackdatedBillingEnum, required: false
      argument :billing_items, GraphQL::Types::JSON, required: false
      argument :commercial_terms, GraphQL::Types::JSON, required: false
      argument :contacts, GraphQL::Types::JSON, required: false
      argument :content, String, required: false
      argument :currency, String, required: false
      argument :description, String, required: false
      argument :execution_mode, Types::Orders::ExecutionModeEnum, required: false
      argument :internal_notes, String, required: false
      argument :legal_text, String, required: false
      argument :metadata, GraphQL::Types::JSON, required: false
      argument :order_type, Types::Orders::OrderTypeEnum, required: true
      argument :owners, [ID], required: false
    end
  end
end
