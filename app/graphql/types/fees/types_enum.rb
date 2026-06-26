# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Fees
    class TypesEnum < Types::BaseEnum
      graphql_name "FeeTypesEnum"

      Fee::FEE_TYPES.each do |type|
        value type
      end
    end
  end
end
