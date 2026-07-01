# frozen_string_literal: true

module V2
  module Subscriptions
    # Terminates a subscription in the new engine: ends every still-active product item
    # and lets each emit its final prorated cycle. Per-item (each item resolves its own
    # rate/period for the closing cycle), so it loops the per-item TerminateService.
    # Separate from the legacy Subscriptions::TerminateService — the two engines run
    # side by side until the migration completes.
    class TerminateService < BaseService
      Result = BaseResult[:subscription_product_items]

      def initialize(subscription:, terminated_at: Time.current)
        @subscription = subscription
        @terminated_at = terminated_at
        super
      end

      def call
        result.subscription_product_items = subscription.subscription_product_items.where(ended_at: nil).map do |item|
          SubscriptionProductItems::TerminateService
            .call!(subscription_product_item: item, terminated_at:)
            .subscription_product_item
        end
        result
      end

      private

      attr_reader :subscription, :terminated_at
    end
  end
end
