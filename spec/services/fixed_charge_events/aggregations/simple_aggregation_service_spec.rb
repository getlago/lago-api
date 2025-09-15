# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedChargeEvents::Aggregations::SimpleAggregationService do
  subject { described_class.new(fixed_charge:, subscription:, charges_from_datetime:, charges_to_datetime:) }

  let(:fixed_charge) { create(:fixed_charge) }
  let(:subscription) { create(:subscription) }
  let(:charges_from_datetime) { 9.days.ago }
  let(:charges_to_datetime) { Time.current }

  context "when there are no events" do
    it "returns 0" do
      expect(subject.call).to eq(0)
    end
  end

  context "when there are events only in this period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 4.days.ago)
    end

    before { events }

    it "returns the simple aggregation" do
      expect(subject.call).to eq(10)
    end
  end

  context "when there are events only in the previous period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 30.days.ago)
    end

    before { events }

    it "returns the simple aggregation" do
      expect(subject.call).to eq(10)
    end
  end

  context "when there are events in the previous period and in this" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 30.days.ago)
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 100, timestamp: 4.days.ago)
    end

    before { events }

    it "returns the simple aggregation" do
      expect(subject.call).to eq(100)
    end
  end
end
