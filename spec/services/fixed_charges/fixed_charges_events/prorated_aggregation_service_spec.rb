# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::FixedChargesEvents::ProratedAggregationService do
  let(:fixed_charge) { create(:fixed_charge) }
  let(:subscription) { create(:subscription) }
  let(:charges_from_datetime) { 9.days.ago } # total duration is 10 days
  let(:charges_to_datetime) { Time.current }

  subject { described_class.new(fixed_charge:, subscription:, charges_from_datetime:, charges_to_datetime:) }

  context "when there are no events" do
    it "returns 0" do
      expect(subject.call).to eq(0)
    end
  end

  context "when there are events only in this period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 2, timestamp: 4.days.ago)
    end

    before { events }

    # the result is 2 * 5/10 = 1
    it "returns the prorated aggregation" do
      expect(subject.call).to eq(1)
    end
  end

  context "when there are events in the previous period and in this" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 100, timestamp: 15.days.ago)
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: Time.current)
    end

    before { events }
    
    # the result is 100 * 9/10 + 10 * 1/10 = 91
    it "returns the prorated aggregation" do
      expect(subject.call).to eq(91)
    end
  end
end
