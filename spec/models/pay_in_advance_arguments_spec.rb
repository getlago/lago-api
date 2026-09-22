# frozen_string_literal: true

require "rails_helper"
RSpec.describe PayInAdvanceArguments do
  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, :pay_in_advance, organization:) }
  let(:event_timestamp) { Time.zone.parse("2026-09-17 15:00:00") }
  let(:subscription) { create(:subscription, organization:, started_at: event_timestamp - 1.day).reload }
  let(:event) do
    create(
      :event,
      organization:,
      external_subscription_id: subscription.external_id,
      timestamp: event_timestamp
    )
  end
  let(:common_event) { Events::CommonFactory.new_instance(source: event) }
  let(:billing_at) { event.timestamp }
  let(:date_service) do
    Subscriptions::DatesService.new_instance(
      subscription,
      billing_at,
      current_usage: true
    )
  end
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: date_service.from_datetime,
      to_datetime: date_service.to_datetime,
      charges_from_datetime: date_service.charges_from_datetime,
      charges_to_datetime: date_service.charges_to_datetime,
      charges_duration: date_service.charges_duration_in_days,
      timestamp: billing_at
    )
  end
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:, boundaries:, event: common_event
    )
  end

  describe "#metered_item" do
    it "uses the supplied metered item instead of legacy arguments" do
      arguments = described_class.new(metered_item:, charge: nil, event: nil)

      expect(arguments.metered_item).to equal(metered_item)
    end

    it "builds a metered item from legacy arguments" do
      arguments = described_class.new(charge:, event:)

      expect(arguments.metered_item.charge).to eq(charge)
      expect(arguments.metered_item.event.timestamp).to eq(event.timestamp)
      expect(arguments.metered_item.boundaries).to have_attributes(
        from_datetime: boundaries.from_datetime,
        to_datetime: boundaries.to_datetime,
        charges_from_datetime: boundaries.charges_from_datetime,
        charges_to_datetime: boundaries.charges_to_datetime,
        charges_duration: boundaries.charges_duration,
        timestamp: boundaries.timestamp
      )
    end

    it "deserializes a metered item payload through its ActiveJob serializer" do
      serialized_metered_item = ActiveJob::Arguments.serialize([metered_item]).first
      arguments = described_class.new(metered_item: serialized_metered_item)

      expect(arguments.metered_item).to have_attributes(
        charge:,
        boundaries: have_attributes(
          from_datetime: boundaries.from_datetime,
          to_datetime: boundaries.to_datetime,
          charges_from_datetime: boundaries.charges_from_datetime,
          charges_to_datetime: boundaries.charges_to_datetime,
          charges_duration: boundaries.charges_duration,
          timestamp: boundaries.timestamp
        ),
        event: have_attributes(timestamp: event.timestamp)
      )
    end
  end

  describe "#lock_key_arguments" do
    it "returns the charge and event identity arguments" do
      arguments = described_class.new(metered_item:)

      expect(arguments.lock_key_arguments).to eq(
        [charge, event.organization_id, event.external_subscription_id, event.transaction_id]
      )
    end
  end
end
