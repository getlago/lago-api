# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriods::FirstPeriodService do
  subject(:result) do
    described_class.call(
      billing_anchor_date:,
      interval_count:,
      interval_unit:,
      billing_timing:,
      timezone:,
      started_at:
    )
  end

  # Created at start unless a context says otherwise; frozen so the "now" clamp is deterministic.
  let(:current_time) { started_at }

  around { |example| Timecop.freeze(current_time) { example.run } }

  let(:interval_count) { 1 }
  let(:interval_unit) { :month }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }

  context "when the subscription starts on the anchor (full first period)" do
    let(:billing_anchor_date) { Date.new(2022, 2, 2) }
    let(:started_at) { Time.utc(2022, 2, 2, 9, 30) }

    context "arrears" do
      it "bills the full first period at its end" do
        expect(result.period_from).to eq(Time.utc(2022, 2, 2))
        expect(result.period_to).to match_datetime(Time.utc(2022, 3, 1, 23, 59, 59))
        expect(result.next_billing_at).to eq(Time.utc(2022, 3, 2))
      end
    end

    context "advance" do
      let(:billing_timing) { :advance }

      it "bills immediately, at the start of the first period" do
        expect(result.period_from).to eq(Time.utc(2022, 2, 2))
        expect(result.period_to).to match_datetime(Time.utc(2022, 3, 1, 23, 59, 59))
        expect(result.next_billing_at).to eq(Time.utc(2022, 2, 2))
      end
    end
  end

  context "when the subscription starts mid-cycle (partial first period)" do
    let(:billing_anchor_date) { Date.new(2022, 2, 1) } # calendar anchor on the 1st
    let(:started_at) { Time.utc(2022, 2, 15, 14) }

    context "arrears" do
      it "bills the partial remainder at the next boundary" do
        expect(result.period_from).to eq(Time.utc(2022, 2, 15))
        expect(result.period_to).to match_datetime(Time.utc(2022, 2, 28, 23, 59, 59))
        expect(result.next_billing_at).to eq(Time.utc(2022, 3, 1))
      end
    end

    context "advance" do
      let(:billing_timing) { :advance }

      it "bills the partial remainder immediately" do
        expect(result.period_from).to eq(Time.utc(2022, 2, 15))
        expect(result.next_billing_at).to eq(Time.utc(2022, 2, 15))
      end
    end
  end

  context "when the subscription started in the past (backdated)" do
    let(:billing_anchor_date) { Date.new(2026, 1, 1) } # calendar anchor on the 1st
    let(:started_at) { Time.utc(2026, 1, 1) }          # active since January...
    let(:current_time) { Time.utc(2026, 6, 15) }       # ...but created in June

    context "arrears" do
      it "bills the current period forward, not the missed months" do
        expect(result.period_from).to eq(Time.utc(2026, 6, 1))
        expect(result.period_to).to match_datetime(Time.utc(2026, 6, 30, 23, 59, 59))
        expect(result.next_billing_at).to eq(Time.utc(2026, 7, 1))
      end

      it "does not put next_billing_at in the past" do
        expect(result.next_billing_at).to be > current_time
      end
    end

    context "advance" do
      let(:billing_timing) { :advance }

      it "bills the current period (its start boundary), not the missed months" do
        expect(result.period_from).to eq(Time.utc(2026, 6, 1))
        expect(result.next_billing_at).to eq(Time.utc(2026, 6, 1))
      end
    end
  end

  context "weekly, mid-cycle start" do
    let(:interval_unit) { :week }
    let(:billing_anchor_date) { Date.new(2022, 1, 3) } # Monday
    let(:started_at) { Time.utc(2022, 1, 5) } # Wednesday

    it "bills the partial week to the next Monday" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 5))
      expect(result.period_to).to match_datetime(Time.utc(2022, 1, 9, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 1, 10))
    end
  end

  context "with a customer timezone" do
    let(:timezone) { "America/New_York" }
    let(:billing_anchor_date) { Date.new(2022, 2, 1) }
    let(:started_at) { Time.utc(2022, 2, 15, 14) } # 2022-02-15 09:00 in New York

    it "anchors the partial period to local midnight" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 15, 5)) # 00:00 NY (EST)
      expect(result.next_billing_at).to eq(Time.utc(2022, 3, 1, 5))
    end
  end
end
