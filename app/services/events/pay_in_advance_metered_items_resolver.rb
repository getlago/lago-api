# frozen_string_literal: true

module Events
  class PayInAdvanceMeteredItemsResolver < BaseService
    Selection = Data.define(:metered_item, :billing_context)
    Result = BaseResult[:selections]

    def initialize(event:)
      @event = Events::CommonFactory.new_instance(source: event)
      super
    end

    def call
      result.selections = charge_selections + billing_segment_selections
      result
    end

    private

    attr_reader :event

    def charge_selections
      return [] unless subscription

      subscription
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metrics: {id: event.billable_metric.id})
        .map do |charge|
          Selection.new(
            metered_item: Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries:, event:),
            billing_context: subscription_context
          )
        end
    end

    def billing_segment_selections
      Events::PayInAdvanceBillingSegmentResolver.call!(event:).billing_segments.map do |billing_segment|
        Selection.new(
          metered_item: Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, event:),
          billing_context: Billing::Context.from(contract: billing_segment.contract)
        )
      end
    end

    def subscription
      @subscription ||= event.subscription
    end

    def subscription_context
      @subscription_context ||= Billing::Context.from(subscription:)
    end

    def boundaries
      @boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: event.timestamp
      )
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        event.timestamp,
        current_usage: true
      )
    end
  end
end
