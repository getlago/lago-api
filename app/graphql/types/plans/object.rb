# frozen_string_literal: true

module Types
  module Plans
    class Object < Types::BaseObject
      graphql_name 'Plan'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :bill_charges_monthly, Boolean
      field :code, String, null: false
      field :description, String
      field :interval, Types::Plans::IntervalEnum, null: false
      field :invoice_display_name, String
      field :name, String, null: false
      field :parent_id, ID, null: true
      field :pay_in_advance, Boolean, null: false
      field :trial_period, Float

      field :charges, [Types::Charges::Object]
      field :taxes, [Types::Taxes::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :active_subscriptions_count, Integer, null: false
      field :charge_count, Integer, null: false, description: 'Number of charges attached to a plan'
      field :customer_count, Integer, null: false, description: 'Number of customers attached to a plan'
      field :draft_invoices_count, Integer, null: false
      field :subscriptions_count, Integer, null: false

      def charges
        object.charges.order(created_at: :asc)
      end

      def charge_count
        object.charges.count
      end

      def customer_count
        object.subscriptions.active.select(:customer_id).distinct.count
      end

      def subscriptions_count
        object.subscriptions.count
      end

      def active_subscriptions_count
        object.subscriptions.active.count
      end

      def draft_invoices_count
        object.subscriptions.joins(:invoices)
          .merge(Invoice.draft)
          .select(:invoice_id)
          .distinct
          .count
      end
    end
  end
end
