# frozen_string_literal: true

module Types
  module CreditNotes
    class StatusTypeEnum < Types::BaseEnum
      graphql_name 'CreditNoteTypeEnum'

      CreditNote::STATUS.each do |type|
        value type
      end
    end
  end
end
