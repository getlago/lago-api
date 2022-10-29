# frozen_string_literal: true

module Types
  module CreditNoteItems
    class Input < Types::BaseInputObject
      graphql_name 'CreditNoteItemInput'

      argument :fee_id, ID, required: true
      argument :credit_amount_cents, GraphQL::Types::BigInt, required: true
      argument :refund_amount_cents, GraphQL::Types::BigInt, required: true
    end
  end
end
