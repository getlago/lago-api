# frozen_string_literal: true

module Types
  module PaymentTerms
    class TermTypeEnum < Types::BaseEnum
      graphql_name "PaymentTermTypeEnum"
      description "Payment term type"

      ::PaymentTerm::TERM_TYPES.each do |code|
        value code
      end
    end
  end
end
