# frozen_string_literal: true

module Types
  module Plans
    class Object < Types::BaseObject
      graphql_name 'Plan'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: false
      field :interval, Types::Plans::IntervalEnum, null: false
      field :pay_in_advance, Boolean, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :trial_period, Float
      field :description, String

      field :charges, [Types::Charges::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :charge_count, Integer, null: false, description: 'Number of charges attached to a plan'
      field :customer_count, Integer, null: false, description: 'Number of customers attached to a plan'

      field :can_be_deleted, Boolean, null: false do
        description 'Check if plan is deletable'
      end

      def charge_count
        object.charges.count
      end

      def customer_count
        object.customers.count
      end

      def can_be_deleted
        object.deletable?
      end
    end
  end
end
