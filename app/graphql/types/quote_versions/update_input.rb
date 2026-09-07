# frozen_string_literal: true

module Types
  module QuoteVersions
    class UpdateInput < BaseInputObject
      graphql_name "UpdateQuoteVersionInput"

      argument :billing_entity_id, ID, required: false
      argument :billing_items, GraphQL::Types::JSON, required: false
      argument :content, String, required: false
      argument :currency, Types::CurrencyEnum, required: false
      argument :id, ID, required: true
    end
  end
end
