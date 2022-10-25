# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class Provider < Types::BaseObject
      graphql_name 'ProviderCustomer'

      field :id, ID, null: false
      field :provider_customer_id, ID, null: true
      field :gocardless_mandate_id, String, null: true
      field :sync_with_provider, Boolean, null: true

      def gocardless_mandate_id
        object.respond_to?(:mandate_id) ? object.mandate_id : nil
      end
    end
  end
end
