# frozen_string_literal: true

module Types
  module Customers
    class BillingConfigurationInput < BaseInputObject
      graphql_name "CustomerBillingConfigurationInput"

      argument :document_locale, String, required: false
    end
  end
end
