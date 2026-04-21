# frozen_string_literal: true

module Types
  module Quotes
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateQuoteInput"

      argument :customer_id, ID, required: true
      argument :order_type, Types::Quotes::OrderTypeEnum, required: true
      argument :owners, [ID], required: false
      argument :subscription_id, ID, required: false
    end
  end
end
