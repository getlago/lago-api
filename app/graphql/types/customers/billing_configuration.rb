# frozen_string_literal: true

module Types
  module Customers
    class BillingConfiguration < Types::BaseObject
      graphql_name "CustomerBillingConfiguration"

      field :document_locale, String
      field :id, ID, null: false
    end
  end
end
