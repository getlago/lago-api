# frozen_string_literal: true

require "rails_helper"

# Adapted from spec/services/subscriptions/dates/monthly_service_spec.rb, expressed
# against the new pure interface:
#
#   DatesService.call(billing_anchor_date:, interval_count:, interval_unit:,
#                     billing_timing:, timezone:, billing_at:)
#     => Result[:period_from, :period_to, :next_billing_at]
#
# Rule (normal, non-terminated): with B = the largest anchor boundary <= billing_at
# in the customer timezone:
#   arrears -> [B - interval, B);  advance -> [B, B + interval)
#   next_billing_at = B + interval (the next boundary, at beginning of day)
#
# period_from is the start of the period (beginning of day); period_to is the
# INCLUSIVE end (end_of_day of the final day), matching the legacy engine.
# The anchor encodes the old "billing_time": calendar => anchor on the 1st,
# anniversary => anchor on the subscription day.
RSpec.describe BillingPeriods::DatesService do
  subject(:result) do
    described_class.call(
      billing_anchor_date:,
      interval_count:,
      interval_unit:,
      billing_timing:,
      timezone:,
      billing_at:
    )
  end

  let(:interval_count) { 1 }
  let(:interval_unit) { :month }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }

  context "calendar (anchor on the 1st), arrears" do
    let(:billing_anchor_date) { Date.new(2022, 1, 1) }
    let(:billing_at) { Time.utc(2022, 3, 1) }

    it "bills the month that just closed" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 1))
      expect(result.period_to).to match_datetime(Time.utc(2022, 2, 28, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 4, 1))
    end

    it_behaves_like "billing period boundaries"

    context "with a customer timezone that shifts across the month boundary" do
      let(:timezone) { "America/New_York" }

      # billing_at is 2022-03-01 00:00 UTC == 2022-02-28 19:00 in New York,
      # so the most recent NY month boundary is Feb 1 -> bill Jan 1..Feb 1.
      it "resolves the period in the customer timezone" do
        expect(result.period_from).to eq(Time.utc(2022, 1, 1, 5))
        expect(result.period_to).to match_datetime(Time.utc(2022, 2, 1, 4, 59, 59))
        expect(result.next_billing_at).to eq(Time.utc(2022, 3, 1, 5))
      end
    end

    context "when billing_at is mid-period (a past date)" do
      let(:billing_at) { Time.utc(2022, 3, 17) }

      it "returns the boundaries of the period that contains it" do
        expect(result.period_from).to eq(Time.utc(2022, 2, 1))
        expect(result.period_to).to match_datetime(Time.utc(2022, 2, 28, 23, 59, 59))
      end
    end
  end

  context "calendar (anchor on the 1st), advance" do
    let(:billing_anchor_date) { Date.new(2022, 1, 1) }
    let(:billing_timing) { :advance }
    let(:billing_at) { Time.utc(2022, 3, 1) }

    it "bills the month that just started" do
      expect(result.period_from).to eq(Time.utc(2022, 3, 1))
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 31, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2022, 4, 1))
    end
  end

  context "anniversary (anchor on the subscription day), arrears" do
    let(:billing_anchor_date) { Date.new(2021, 2, 2) }
    let(:billing_at) { Time.utc(2022, 3, 2) }

    it "bills from anchor-day to anchor-day" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 2))
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 1, 23, 59, 59))
    end
  end

  context "month-end anchor (the 31st), arrears" do
    let(:billing_anchor_date) { Date.new(2021, 1, 31) }
    let(:billing_at) { Time.utc(2022, 3, 31) }

    # Feb clamps to the 28th, but March re-derives from the anchor to the 31st
    # (it does not drift to Mar 28). The period [Feb 28, Mar 31) ends Mar 30.
    it "clamps short months without drifting" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 28))
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 30, 23, 59, 59))
    end

    it_behaves_like "billing period boundaries"
  end

  context "leap year, arrears" do
    let(:billing_anchor_date) { Date.new(2024, 1, 31) }
    let(:billing_at) { Time.utc(2024, 2, 29) }

    it "lands on Feb 29" do
      expect(result.period_from).to eq(Time.utc(2024, 1, 31))
      expect(result.period_to).to match_datetime(Time.utc(2024, 2, 28, 23, 59, 59))
    end
  end

  context "multi-month interval (quarterly), arrears" do
    let(:interval_count) { 3 }
    let(:billing_anchor_date) { Date.new(2022, 1, 1) }
    let(:billing_at) { Time.utc(2022, 4, 1) }

    it "spans three months" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 1))
      expect(result.period_to).to match_datetime(Time.utc(2022, 3, 31, 23, 59, 59))
    end
  end
end
