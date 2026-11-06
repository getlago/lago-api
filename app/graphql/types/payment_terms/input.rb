# frozen_string_literal: true

module Types
  module PaymentTerms
    class Input < BaseInputObject
      graphql_name "PaymentTermInput"
      description "Structured payment term input"

      argument :day_of_month, Integer, required: false
      argument :days, Integer, required: false
      argument :month_offset, Integer, required: false
      argument :term_type, Types::PaymentTerms::TermTypeEnum, required: true

      # Clients echoing a PaymentTerm back send the non-applicable fields as null.
      def prepare
        to_h.compact
      end
    end
  end
end
