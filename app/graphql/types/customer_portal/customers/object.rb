# frozen_string_literal: true

module Types
  module CustomerPortal
    module Customers
      class Object < Types::BaseObject
        graphql_name "CustomerPortalCustomer"

        field :id, ID, null: false

        field :applicable_timezone, Types::TimezoneEnum, null: false
        field :currency, Types::CurrencyEnum, null: true
        field :display_name, String, null: false
        field :email, String, null: true
        field :firstname, String
        field :lastname, String
        field :legal_name, String, null: true
        field :legal_number, String, null: true
        field :name, String
        field :tax_identification_number, String, null: true

        field :billing_configuration, Types::Customers::BillingConfiguration, null: true

        # Billing address
        field :address_line1, String, null: true
        field :address_line2, String, null: true
        field :city, String, null: true
        field :country, Types::CountryCodeEnum, null: true
        field :state, String, null: true
        field :zipcode, String, null: true

        field :shipping_address, Types::Customers::Address, null: true

        def billing_configuration
          {
            id: "#{object&.id}-c0nf",
            document_locale: object&.document_locale
          }
        end
      end
    end
  end
end
