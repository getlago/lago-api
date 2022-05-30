# frozen_string_literal: true

module Types
  module Customers
    class SingleObject < Types::Customers::Object
      graphql_name 'CustomerDetails'

      field :invoices, [Types::Invoices::Object]
      field :subscriptions, [Types::Subscriptions::Object], resolver: Resolvers::Customers::SubscriptionsResolver
      field :applied_coupons, [Types::AppliedCoupons::Object], null: true
      field :applied_add_ons, [Types::AppliedAddOns::Object], null: true

      def invoices
        object.invoices.order(issuing_date: :desc)
      end

      def applied_coupons
        object.applied_coupons.active.order(created_at: :asc)
      end

      def applied_add_ons
        object.applied_add_ons.order(created_at: :asc)
      end
    end
  end
end
