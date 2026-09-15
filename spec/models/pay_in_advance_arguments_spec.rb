# frozen_string_literal: true

require "rails_helper"
RSpec.describe PayInAdvanceArguments do
  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, :pay_in_advance, organization:) }
  let(:event) { create(:event, organization:) }
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: event.timestamp,
      to_datetime: event.timestamp,
      charges_from_datetime: event.timestamp,
      charges_to_datetime: event.timestamp,
      charges_duration: 0,
      timestamp: event.timestamp
    )
  end
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:, boundaries:, event: Events::CommonFactory.new_instance(source: event)
    )
  end

  describe "#metered_item" do
    it "uses the supplied metered item instead of legacy arguments" do
      arguments = described_class.new(metered_item:, charge: nil, event: nil)

      expect(arguments.metered_item).to equal(metered_item)
    end

    it "builds a metered item from legacy arguments" do
      arguments = described_class.new(charge:, event:)

      expect(arguments.metered_item).to have_attributes(
        charge:,
        event: have_attributes(timestamp: event.timestamp)
      )
      expect(arguments.metered_item.boundaries).to have_attributes(
        from_datetime: event.timestamp,
        to_datetime: event.timestamp,
        charges_from_datetime: event.timestamp,
        charges_to_datetime: event.timestamp,
        charges_duration: 0,
        timestamp: event.timestamp
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
