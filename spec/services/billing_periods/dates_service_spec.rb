# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriods::DatesService do
  subject(:result) do
    described_class.call(
      billing_anchor_date:,
      interval_count:,
      interval_unit:,
      billing_timing:,
      timezone:,
      period_started_at:
    )
  end

  let(:billing_anchor_date) { Date.new(2026, 2, 1) }
  let(:interval_count) { 1 }
  let(:interval_unit) { :month }
  let(:billing_timing) { :arrears }
  let(:timezone) { "UTC" }
  let(:period_started_at) { nil }

  describe "first period (no period_started_at)" do
    it "starts at the anchor and ends one interval later" do
      expect(result.period_from).to eq(Time.utc(2026, 2, 1))
      expect(result.period_to).to eq(Time.utc(2026, 3, 1))
    end

    context "with arrears timing" do
      it "bills at the end of the period" do
        expect(result.next_billing_at).to eq(Time.utc(2026, 3, 1))
      end
    end

    context "with advance timing" do
      let(:billing_timing) { :advance }

      it "bills at the start of the period" do
        expect(result.next_billing_at).to eq(Time.utc(2026, 2, 1))
      end
    end
  end

  describe "advancing to the next period" do
    let(:period_started_at) { Time.utc(2026, 3, 1) }

    it "describes the period starting at the given boundary" do
      expect(result.period_from).to eq(Time.utc(2026, 3, 1))
      expect(result.period_to).to eq(Time.utc(2026, 4, 1))
      expect(result.next_billing_at).to eq(Time.utc(2026, 4, 1))
    end
  end

  describe "month-end anchoring does not drift" do
    let(:billing_anchor_date) { Date.new(2026, 1, 31) }

    it "clamps Feb but re-derives Mar from the anchor (not Feb 28 + 1 month)" do
      # First period: Jan 31 -> Feb 28
      expect(result.period_from).to eq(Time.utc(2026, 1, 31))
      expect(result.period_to).to eq(Time.utc(2026, 2, 28))
    end

    context "when advancing from the clamped Feb boundary" do
      let(:period_started_at) { Time.utc(2026, 2, 28) }

      it "lands on Mar 31, not Mar 28" do
        expect(result.period_from).to eq(Time.utc(2026, 2, 28))
        expect(result.period_to).to eq(Time.utc(2026, 3, 31))
      end
    end
  end

  describe "weekly interval" do
    let(:interval_unit) { :week }
    let(:billing_anchor_date) { Date.new(2026, 2, 2) } # a Monday

    it "advances by 7 days" do
      expect(result.period_from).to eq(Time.utc(2026, 2, 2))
      expect(result.period_to).to eq(Time.utc(2026, 2, 9))
    end
  end

  describe "daily interval" do
    let(:interval_unit) { :day }

    it "advances by one day" do
      expect(result.period_from).to eq(Time.utc(2026, 2, 1))
      expect(result.period_to).to eq(Time.utc(2026, 2, 2))
    end
  end

  describe "multi-interval count" do
    let(:interval_count) { 3 }

    it "spans three months" do
      expect(result.period_from).to eq(Time.utc(2026, 2, 1))
      expect(result.period_to).to eq(Time.utc(2026, 5, 1))
    end
  end

  describe "customer timezone" do
    let(:timezone) { "America/New_York" }

    it "anchors at start of day in the customer timezone, expressed in UTC" do
      # 2026-02-01 00:00 in New York (UTC-5) is 05:00 UTC
      expect(result.period_from).to eq(Time.utc(2026, 2, 1, 5))
      expect(result.period_to).to eq(Time.utc(2026, 3, 1, 5))
    end
  end
end
