# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module CreditNoteItems
    class Input < Types::BaseInputObject
      graphql_name "CreditNoteItemInput"

      argument :amount_cents, GraphQL::Types::BigInt, required: true
      argument :fee_id, ID, required: true
    end
  end
end
