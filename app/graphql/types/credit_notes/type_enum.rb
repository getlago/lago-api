# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module CreditNotes
    class TypeEnum < Types::BaseEnum
      graphql_name "CreditNoteTypeEnum"

      CreditNote::TYPES.each do |type|
        value type
      end
    end
  end
end
