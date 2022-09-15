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
      field :bill_charges_monthly, Boolean

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

      # How many times plan was applied to customers
      def customer_count
        base_count = object.subscriptions.active.count

        extended_plan_ids = object.extended_plans.pluck(:id)
        return base_count if extended_plan_ids.empty?

        extended_count = Subscription.active.where(plan_id: extended_plan_ids).count

        base_count + extended_count
      end

      def can_be_deleted
        object.deletable?
      end

      def code
        return object.overridden_plan.code if object.overridden_plan_id

        object.code
      end
    end
  end
end
