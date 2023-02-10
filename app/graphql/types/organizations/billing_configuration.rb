# frozen_string_literal: true

module Types
  module Organizations
    class BillingConfiguration < Types::BaseObject
      graphql_name 'OrganizationBillingConfiguration'

      field :id, ID, null: false
      field :vat_rate, Float, null: false
      field :invoice_footer, String
      field :invoice_grace_period, Integer, null: false
      field :document_locale, String
    end
  end
end
