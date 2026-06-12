# frozen_string_literal: true

module Types
  module RateCards
    class Object < Types::BaseObject
      graphql_name "RateCard"
      description "Base rate card"

      dataload_association :product, :product_filter

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :name, String, null: false

      field :billing_timing, Types::RateCards::BillingTimingEnum, null: false
      field :currency, Types::CurrencyEnum, null: false
      field :display_on_invoice, Boolean, null: false
      field :proration, Boolean, null: false
      field :regroup_paid_fees, Types::RateCards::RegroupPaidFeesEnum, null: true

      field :applied_pricing_unit_code, String, null: true
      field :wallet_targetable, Boolean, null: true

      # Lock signals for clients: deletion locks at any plan/subscription
      # attachment, rate edits lock once a subscription bills the card.
      field :attached_to_plan_or_subscription, Boolean, null: false, method: :attached_to_plan_or_subscription?
      field :attached_to_subscriptions, Boolean, null: false, method: :attached_to_subscriptions?

      field :product, Types::Products::Object, null: false
      field :product_filter, Types::ProductFilters::Object, null: true
      field :rates, [Types::RateCardRates::Object], null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
