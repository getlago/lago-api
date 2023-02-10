# frozen_string_literal: true

module Types
  module Customers
    class BillingConfiguration < Types::BaseObject
      graphql_name 'CustomerBillingConfiguration'

      field :id, ID, null: false
      field :document_locale, String
    end
  end
end
