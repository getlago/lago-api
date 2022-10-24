# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class Gocardless < Types::BaseObject
      graphql_name 'GocardlessCustomer'

      field :id, ID, null: false
      field :provider_customer_id, ID, null: true
      field :mandate_id, String, null: true
      field :sync_with_provider, Boolean, null: true
    end
  end
end
