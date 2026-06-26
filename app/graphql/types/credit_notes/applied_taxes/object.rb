# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module CreditNotes
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name "CreditNoteAppliedTax"
        implements Types::Taxes::AppliedTax

        field :base_amount_cents, GraphQL::Types::BigInt, null: false
        field :credit_note, Types::CreditNotes::Object, null: false
      end
    end
  end
end
