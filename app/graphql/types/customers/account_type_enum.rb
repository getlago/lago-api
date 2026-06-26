# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Customers
    class AccountTypeEnum < Types::BaseEnum
      graphql_name "CustomerAccountTypeEnum"

      Customer::ACCOUNT_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
