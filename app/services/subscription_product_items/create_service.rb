# frozen_string_literal: true

module SubscriptionProductItems
  # Adds a product item to a subscription. Beyond writing the row, it seeds the billing
  # clock: it resolves the active rate (to learn the interval and timing) and asks
  # FirstPeriodService for the initial next_billing_at, so the scheduler picks the item
  # up at the right boundary. Without a resolvable rate there is no interval to bill on,
  # so creation fails rather than leaving an item the clock can never advance.
  class CreateService < BaseService
    Result = BaseResult[:subscription_product_item]

    def initialize(subscription:, product_item:, started_at:, billing_anchor_date: nil, units: nil)
      @subscription = subscription
      @product_item = product_item
      @started_at = started_at
      @billing_anchor_date = billing_anchor_date
      @units = units
      super
    end

    def call
      subscription_product_item = SubscriptionProductItem.new(
        organization: subscription.organization,
        subscription:,
        product_item:,
        units:,
        started_at:,
        billing_anchor_date: anchor_date
      )

      rate_result = ResolveRateService.call(subscription_product_item:, datetime: started_at)
      return result.not_found_failure!(resource: "rate") unless rate_result.success?

      first_period = BillingPeriods::FirstPeriodService
        .from_subscription_product_item(subscription_product_item, rate: rate_result.rate)
      subscription_product_item.next_billing_at = first_period.next_billing_at
      subscription_product_item.save!

      result.subscription_product_item = subscription_product_item
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :product_item, :started_at, :billing_anchor_date, :units

    def anchor_date
      billing_anchor_date || started_at.to_date
    end
  end
end
