# frozen_string_literal: true

module Types
  module RateCards
    class Object < Types::BaseObject
      graphql_name "RateCard"
      description "Base rate card"

      dataload_association :product, :product_filter, :taxes

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

      # Lock signals for clients: deletion locks at any plan/subscription
      # attachment, rate edits lock once a subscription bills the card.
      field :attached_to_plan_or_subscription, Boolean, null: false
      field :attached_to_subscriptions, Boolean, null: false

      field :product, Types::Products::Object, null: false
      field :product_filter, Types::ProductFilters::Object, null: true
      field :taxes, [Types::Taxes::Object], null: false

      field :active_rate, Types::RateCardRates::Object, null: true
      field :rates_count, Integer, null: false

      field :next_pending_rate, Types::RateCardRates::Object, null: true do
        argument :as_of, GraphQL::Types::ISO8601DateTime, required: false,
          description: "Perspective to resolve the soonest pending rate from. Defaults to now."
      end

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      def rates_count
        dataloader.with(Sources::CountByForeignKey, RateCardRate, :rate_card_id).load(object.id)
      end

      def attached_to_plan_or_subscription
        dataloader.with(Sources::AttachedToPlanOrSubscription, :rate_card).load(object.id)
      end

      def attached_to_subscriptions
        dataloader.with(Sources::AttachedToSubscriptions).load(object.id)
      end

      def active_rate
        dataloader.with(Sources::ActiveRate).load(object.id)
      end

      def next_pending_rate(as_of: nil)
        dataloader.with(Sources::NextPendingRate, as_of || Time.current).load(object.id)
      end
    end
  end
end
