# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module PaymentMethods
    class Details < Types::BaseObject
      graphql_name "PaymentMethodDetails"

      field :brand, String, null: true
      field :expiration_month, String, null: true
      field :expiration_year, String, null: true
      field :last4, String, null: true
      field :type, String, null: true
    end
  end
end
