# frozen_string_literal: true

module Events
  class PayInAdvanceBillingSegmentResolver < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(event:)
      @event = event
      super
    end

    def call
      unless organization.product_catalog_enabled? && billable_metric
        result.billing_segments = BillingSegment.none
        return result
      end

      result.billing_segments = billing_segments
      result
    end

    private

    attr_reader :event

    delegate :billable_metric, :organization, to: :event

    def billing_segments
      BillingSegment.status_processing
        .joins(:contract, contract_rate_card: {rate_card: :product})
        .where(
          contracts: {external_id: event.external_subscription_id, status: Contract::LIVE_STATUSES},
          rate_cards: {billing_timing: :advance},
          products: {billable_metric_id: billable_metric.id, product_type: :metered},
          organization_id: organization.id
        )
        .where(
          "date_trunc('millisecond', billing_segments.started_at::timestamp) <= ?::timestamp AND " \
            "date_trunc('millisecond', billing_segments.ended_at::timestamp) >= ?",
          event.timestamp,
          event.timestamp
        )
    end
  end
end
