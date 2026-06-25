# frozen_string_literal: true

require "rails_helper"

# Yearly interval. Calendar billing anchors to Jan 1; anniversary to the
# subscription's day/month. Feb 29 is the year-level month-end case.
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
  let(:interval_unit) { :year }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }

  context "calendar (anchor on Jan 1), arrears" do
    let(:billing_anchor_date) { Date.new(2020, 1, 1) }
    let(:billing_at) { Time.utc(2023, 1, 1) }

    it "bills the year that just closed" do
      expect(result.period_from).to eq(Time.utc(2022, 1, 1))
      expect(result.period_to).to match_datetime(Time.utc(2022, 12, 31, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2024, 1, 1))
    end

    it_behaves_like "billing period boundaries"
  end

  context "calendar, advance" do
    let(:billing_anchor_date) { Date.new(2020, 1, 1) }
    let(:billing_timing) { :advance }
    let(:billing_at) { Time.utc(2023, 1, 1) }

    it "bills the year that just started" do
      expect(result.period_from).to eq(Time.utc(2023, 1, 1))
      expect(result.period_to).to match_datetime(Time.utc(2023, 12, 31, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2024, 1, 1))
    end
  end

  context "anniversary (anchor on the subscription day/month), arrears" do
    let(:billing_anchor_date) { Date.new(2021, 2, 2) }
    let(:billing_at) { Time.utc(2023, 2, 2) }

    it "bills from anniversary to anniversary" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 2))
      expect(result.period_to).to match_datetime(Time.utc(2023, 2, 1, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2024, 2, 2))
    end
  end

  context "Feb 29 anchor, arrears" do
    let(:billing_anchor_date) { Date.new(2020, 2, 29) }
    let(:billing_at) { Time.utc(2023, 2, 28) }

    # Non-leap years clamp to Feb 28, but the anchor is re-derived each year, so
    # the boundary returns to Feb 29 in the next leap year (2024) — no drift.
    it "clamps to Feb 28 off leap years and returns to Feb 29 on leap years" do
      expect(result.period_from).to eq(Time.utc(2022, 2, 28))
      expect(result.period_to).to match_datetime(Time.utc(2023, 2, 27, 23, 59, 59))
      expect(result.next_billing_at).to eq(Time.utc(2024, 2, 29))
    end
  end
end
