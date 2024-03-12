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
      field :parent, Types::Plans::Object, null: true
      field :pay_in_advance, Boolean, null: false
      field :trial_period, Float

      field :charge_groups, [Types::ChargeGroups::Object]
      field :charges, [Types::Charges::Object]
      field :taxes, [Types::Taxes::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :active_subscriptions_count, Integer, null: false
      field :charge_groups_count, Integer, null: false, description: 'Number of charge groups attached to a plan'
      field :charges_count, Integer, null: false, description: 'Number of charges attached to a plan'
      field :customers_count, Integer, null: false, description: 'Number of customers attached to a plan'
      field :draft_invoices_count, Integer, null: false
      field :subscriptions_count, Integer, null: false

      def charges
        object.charges.order(created_at: :asc)
      end

      def charge_groups
        object.charge_groups.order(created_at: :asc)
      end

      def charges_count
        object.charges.count
      end

      def charge_groups_count
        object.charge_groups.count
      end

      def subscriptions_count
        count = object.subscriptions.count
        return count unless object.children

        count + object.children.joins(:subscriptions).select('subscriptions.id').distinct.count
      end
    end
  end
end
