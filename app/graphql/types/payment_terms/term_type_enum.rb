# frozen_string_literal: true

module Types
  module PaymentTerms
    class TermTypeEnum < Types::BaseEnum
      graphql_name "PaymentTermTypeEnum"
      description "Payment term type"

      ::PaymentTerm::FIELDS_BY_TERM_TYPE.each_key do |code|
        value code
      end
    end
  end
end
