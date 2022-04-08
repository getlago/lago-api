# frozen_string_literal: true

module Types
  module Customers
    class SingleObject < Types::BaseObject
      graphql_name 'CustomerDetails'

      field :customer, Types::Customers::Object, method: :itself
      field :subscriptions, [Types::Subscriptions::Object]
      field :invoices, [Types::Invoices::Object]
    end
  end
end
