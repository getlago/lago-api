# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Re-derives the periods of every subscription affected by a change to an input they share: a
    # plan's interval or monthly-charges flag, or the applicable timezone of a customer or billing
    # entity.
    class RefreshAllService < BaseService
      Result = BaseResult[:enqueued_count]

      def initialize(owner:)
        @owner = owner

        super
      end

      def call
        count = 0

        subscriptions.find_each do |subscription|
          Subscriptions::BillingPeriods::UpsertJob.perform_later(subscription.id)
          count += 1
        end

        result.enqueued_count = count
        result
      end

      private

      attr_reader :owner

      def subscriptions
        scope = case owner
        when Plan then Subscription.where(plan_id: owner.id)
        when Customer then Subscription.where(customer_id: owner.id)
        when BillingEntity then Subscription.joins(:customer).where(customers: {billing_entity_id: owner.id})
        else raise ArgumentError, "unsupported owner: #{owner.class}"
        end

        scope.where(status: %i[active terminated])
      end
    end
  end
end
