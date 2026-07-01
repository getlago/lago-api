# frozen_string_literal: true

module SubscriptionProductItems
  # Materializes a subscription's billing units from its plan: one
  # subscription_product_item per plan_product_item, each seeding its own billing
  # clock (via CreateService). This is the plan-based subscribe flow (Dive-In 2,
  # Scenario 1) — subscribing to a plan copies its items onto the subscription.
  #
  # No-op for contract subscriptions (no plan). Idempotent guard lives on the SPI
  # uniqueness index, so re-running won't double-create the same item.
  class MaterializeService < BaseService
    Result = BaseResult[:subscription_product_items]

    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      result.subscription_product_items = plan_product_items.map do |plan_product_item|
        CreateService.call!(
          subscription:,
          product_item: plan_product_item.product_item,
          started_at: subscription.started_at,
          units: plan_product_item.units
        ).subscription_product_item
      end
      result
    end

    private

    attr_reader :subscription

    def plan_product_items
      subscription.plan&.plan_product_items || []
    end
  end
end
