# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module CreditNoteItems
    class Estimate < Types::BaseObject
      graphql_name "CreditNoteItemEstimate"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :fee, Types::Fees::Object, null: false
    end
  end
end
