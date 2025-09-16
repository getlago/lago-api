# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedChargeEvents::Aggregations::ProratedAggregationService do
  subject { described_class.new(fixed_charge:, subscription:, charges_from_datetime:, charges_to_datetime:) }

  let(:fixed_charge) { create(:fixed_charge) }
  let(:subscription) { create(:subscription) }
  let(:charges_from_datetime) { 9.days.ago } # total duration is 10 days
  let(:charges_to_datetime) { Time.current }

  context "when there are no events" do
    it "returns 0" do
      expect(subject.call).to eq(0)
    end
  end

  context "when there are events only in this period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 2, timestamp: 4.days.ago, created_at: 4.days.ago)
    end

    before { events }

    # the result is 2 * 5/10 = 1
    it "returns the prorated aggregation" do
      expect(subject.call).to eq(1)
    end
  end

  context "when there are only events in the previous period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 30.days.ago, created_at: 30.days.ago)
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 100, timestamp: 15.days.ago, created_at: 15.days.ago)
    end

    before { events }

    # the result is 100 * 10/10 = 100
    it "returns the prorated aggregation" do
      expect(subject.call).to eq(100)
    end
  end

  context "when there are events in the previous period and in this" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 100, timestamp: 15.days.ago, created_at: 15.days.ago)
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: Time.current, created_at: Time.current)
    end

    before { events }

    # the result is 100 * 9/10 + 10 * 1/10 = 91
    it "returns the prorated aggregation" do
      expect(subject.call).to eq(91)
    end
  end

  context "when events are issued for the next billing period" do
    let(:events) do
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 20, timestamp: 10.days.ago, created_at: 10.days.ago)
      create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 1.day.from_now, created_at: 5.days.ago)
    end

    before { events }

    context "when aggregating for current period" do
      it "returns the prorated aggregation" do
        # 20 * 10/10 = 20
        expect(subject.call).to eq(20)
      end
    end

    context "when aggregating for the next billing period" do
      let(:charges_from_datetime) { 1.day.from_now } # total duration is 10 days
      let(:charges_to_datetime) { 10.days.from_now }

      it "returns the prorated aggregation" do
        # 10 * 10/10 = 10
        expect(subject.call).to eq(10)
      end
    end

    context "when last event is issued after event for the next billing period cancels event for the next billing period" do
      let(:events) do
        create(:fixed_charge_event, fixed_charge:, subscription:, units: 20, timestamp: 10.days.ago, created_at: 10.days.ago)
        create(:fixed_charge_event, fixed_charge:, subscription:, units: 10, timestamp: 5.days.from_now, created_at: 5.days.ago)
        create(:fixed_charge_event, fixed_charge:, subscription:, units: 100, timestamp: Time.current, created_at: Time.current)
      end

      context "when aggregating for the current period" do
        it "returns the prorated aggregation" do
          # 20 * 9/10 + 100 * 1/10 = 28
          expect(subject.call).to eq(28)
        end
      end

      context "when aggregating for the next billing period" do
        let(:charges_from_datetime) { 1.day.from_now } # total duration is 10 days
        let(:charges_to_datetime) { 10.days.from_now }

        it "returns the prorated aggregation erasing the event for the next billing period created before last event of this billing period" do
          # 100 * 10/10 = 100
          expect(subject.call).to eq(100)
        end
      end
    end

    context "when having a lot of events issued for this and following billing periods" do
      let(:events_matrix) do
        [
          { units: 10, timestamp: Date.new(2025, 1, 1), created_at: Date.new(2025, 1, 1) }, # 1 Jan for 1 Jan
          { units: 5, timestamp: Date.new(2025, 2, 1), created_at: Date.new(2025, 1, 5) }, # 5 Jan for 1 Feb
          { units: 77, timestamp: Date.new(2025, 1, 22), created_at: Date.new(2025, 1, 7) }, # 7 Jan for 22 Jan
          { units: 7, timestamp: Date.new(2025, 1, 20), created_at: Date.new(2025, 1, 10) }, # 10 Jan for 20 Jan
          { units: 12, timestamp: Date.new(2025, 3, 1), created_at: Date.new(2025, 1, 20) }, # 20 Jan for 1 Mar
          { units: 70, timestamp: Date.new(2025, 2, 10), created_at: Date.new(2025, 1, 30) } # 30 Jan for 10 Feb
        ]
      end

      let(:events) do
        events_matrix.map do |event|
          create(:fixed_charge_event, fixed_charge:, subscription:, **event)
        end
      end

      context "when billing period is January" do
        let(:charges_from_datetime) { Date.new(2025, 1, 1) }
        let(:charges_to_datetime) { Date.new(2025, 1, 31) }

        it "returns the prorated aggregation" do
          # 10 * 19/31 + 7 * 12/31 = 8.8387
          expect(subject.call.round(2)).to eq(8.84)
        end
      end

      context "when billing period is February" do
        let(:charges_from_datetime) { Date.new(2025, 2, 1) }
        let(:charges_to_datetime) { Date.new(2025, 2, 28) }

        it "returns the prorated aggregation" do
          # 7 * 9/28 + 70 * 19/28 = 49.75
          expect(subject.call.round(2)).to eq(49.75)
        end
      end

      context "when billing period is March" do
        let(:charges_from_datetime) { Date.new(2025, 3, 1) }
        let(:charges_to_datetime) { Date.new(2025, 3, 31) }

        it "returns the prorated aggregation" do
          # 70 * 31/31 = 70
          expect(subject.call.round(2)).to eq(70)
        end
      end
    end
  end
end
