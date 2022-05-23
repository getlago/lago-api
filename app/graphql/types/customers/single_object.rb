# frozen_string_literal: true

module Types
  module Customers
    class SingleObject < Types::Customers::Object
      graphql_name 'CustomerDetails'

      field :invoices, [Types::Invoices::Object]
      field :subscriptions, [Types::Subscriptions::Object], resolver: Resolvers::Customers::SubscriptionsResolver
      field :applied_coupons, [Types::AppliedCoupons::Object], null: true

      def invoices
        object.invoices.order(issuing_date: :desc)
      end

      def applied_coupon
        object.applied_coupons.active.order(created_at: :asc).first
      end
    end
  end
end
