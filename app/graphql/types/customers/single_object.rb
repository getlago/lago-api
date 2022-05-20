# frozen_string_literal: true

module Types
  module Customers
    class SingleObject < Types::Customers::Object
      graphql_name 'CustomerDetails'

      field :invoices, [Types::Invoices::Object]
      field :subscriptions, [Types::Subscriptions::Object], resolver: Resolvers::Customers::SubscriptionsResolver

      def invoices
        object.invoices.order(issuing_date: :desc)
      end
    end
  end
end
