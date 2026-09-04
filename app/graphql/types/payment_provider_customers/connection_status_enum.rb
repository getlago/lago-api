# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class ConnectionStatusEnum < Types::BaseEnum
      graphql_name "PaymentProviderConnectionStatusEnum"

      ::PaymentProviderCustomers::BaseCustomer::CONNECTION_STATUSES.each_value do |status|
        value status
      end
    end
  end
end
