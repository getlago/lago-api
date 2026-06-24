# frozen_string_literal: true

module SubscriptionProductItems
  # Resolves the active rate for a subscription product item at a given moment.
  #
  # v1.a walks straight to the catalog: the plan's plan_product_item for this product
  # item points at the rate_card, and the active rate is the latest rate whose
  # effective_datetime is on or before `datetime`. The rate_phase / rate_override
  # layer (subscription- and plan-level overrides) plugs in here in v2.
  #
  #   rate_card timeline: $0.10 (eff 2026-01-01), $0.15 (eff 2026-07-01)
  #   resolve at 2026-03-01 => $0.10 ; resolve at 2026-08-01 => $0.15
  class ResolveRateService < BaseService
    Result = BaseResult[:rate]

    def initialize(subscription_product_item:, datetime:)
      @subscription_product_item = subscription_product_item
      @datetime = datetime
      super
    end

    def call
      return result.not_found_failure!(resource: "rate") unless rate

      result.rate = rate
      result
    end

    private

    attr_reader :subscription_product_item, :datetime

    def rate
      @rate ||= rate_card
        &.rates
        &.where("effective_datetime <= ?", datetime)
        &.order(effective_datetime: :desc)
        &.first
    end

    def rate_card
      plan_product_item&.rate_card
    end

    # For v1.a there is a single plan_product_item per product item. Filter-scoped
    # cards (multiple per product item) are resolved per filter — deferred.
    def plan_product_item
      plan&.plan_product_items&.find_by(product_item_id: subscription_product_item.product_item_id)
    end

    def plan
      subscription_product_item.subscription.plan
    end
  end
end
