# frozen_string_literal: true

class PayInAdvanceArguments
  # Centralizes the migration from legacy charge/event job arguments to MeteredItem.
  def initialize(metered_item: nil, charge: nil, boundaries: nil, event: nil)
    @metered_item = metered_item
    @charge = charge
    @boundaries = boundaries
    @event = event
  end

  def metered_item
    if @metered_item.is_a?(Hash)
      payload = @metered_item.with_indifferent_access
      @metered_item = Fees::ChargeService::MeteredItem.from_charge(
        charge: payload[:charge],
        boundaries: BillingPeriodBoundaries.new(**payload[:boundaries].symbolize_keys),
        event: Events::CommonFactory.new_instance(source: payload[:event])
      )
    end

    return @metered_item if @metered_item

    @metered_item = Fees::ChargeService::MeteredItem.from_charge(
      charge:,
      boundaries: boundaries || build_boundaries,
      event: normalized_event
    )
  end

  def lock_key_arguments
    [
      metered_item.charge,
      metered_item.event.organization_id,
      metered_item.event.external_subscription_id,
      metered_item.event.transaction_id
    ]
  end

  private

  attr_reader :charge, :boundaries, :event

  def normalized_event
    @normalized_event ||= Events::CommonFactory.new_instance(source: event)
  end

  def build_boundaries
    if normalized_event.subscription
      date_service = Subscriptions::DatesService.new_instance(
        normalized_event.subscription,
        normalized_event.timestamp,
        current_usage: true
      )

      return BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: normalized_event.timestamp
      )
    end

    BillingPeriodBoundaries.new(
      from_datetime: normalized_event.timestamp,
      to_datetime: normalized_event.timestamp,
      charges_from_datetime: normalized_event.timestamp,
      charges_to_datetime: normalized_event.timestamp,
      charges_duration: 0,
      timestamp: normalized_event.timestamp
    )
  end
end
