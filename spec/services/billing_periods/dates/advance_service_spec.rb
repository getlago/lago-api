# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriods::Dates::AdvanceService do
  describe ".call" do
    subject(:result) do
      described_class.call(
        billing_anchor_date:,
        options:,
        started_at:,
        rates:,
        range:,
        subscription_rate_card:
      )
    end

    let(:organization) { create(:organization) }
    let(:rate_card) { create(:rate_card, :advance, organization:) }
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        rate_card:,
        billing_anchor_date:,
        started_at:
      )
    end
    let(:end_of_day) { ->(date) { Time.zone.parse(date).end_of_day } }
    let(:billing_anchor_date) { Date.parse("2022-02-01") }
    let(:started_at) { Time.zone.parse("2022-02-01") }
    let(:range) { Date.parse("2022-03-01")..Date.parse("2022-03-31") }
    let(:exclude_out_of_range) { false }
    let(:options) do
      BillingPeriods::DatesService::Options.new(
        timezone: "UTC",
        exclude_out_of_range:,
        realign_billing_anchor: false,
        termination: false
      )
    end
    let(:rates) { [rate] }
    let(:rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2022-02-01"),
        billing_interval_count: 1,
        billing_interval_unit: "month"
      )
    end

    context "when excluding periods outside the range" do
      let(:range) { Date.parse("2022-03-15")..Date.parse("2022-03-15") }
      let(:exclude_out_of_range) { true }

      it "keeps full periods overlapping the range" do
        expect(result.next_billing_at).to eq(Time.zone.parse("2022-04-01"))
        expect(result.periods.map { [it.period_from, it.period_to, it.next_billing_at, it.rate] }).to eq(
          [
            [
              Time.zone.parse("2022-03-01"),
              end_of_day.call("2022-03-31"),
              Time.zone.parse("2022-04-01"),
              rate
            ]
          ]
        )
      end

      it "does not clamp the period to the requested range" do
        period = result.periods.sole

        expect(period.period_from).to eq(Time.zone.parse("2022-03-01"))
        expect(period.period_to).to eq(end_of_day.call("2022-03-31"))
        expect(period.proration_ratio).to eq(1)
        expect(period.consumed_ratio).to eq(15.fdiv(31))
      end
    end

    it "returns the period starting at the billing boundary" do
      expect(result.next_billing_at).to eq(Time.zone.parse("2022-04-01"))
      expect(result.periods.map { [it.period_from, it.period_to, it.next_billing_at, it.rate] }).to eq(
        [
          [
            Time.zone.parse("2022-03-01"),
            end_of_day.call("2022-03-31"),
            Time.zone.parse("2022-04-01"),
            rate
          ]
        ]
      )
    end

    context "with different rate effective dates" do
      let(:billing_anchor_date) { Date.parse("2026-08-03") }
      let(:started_at) { Time.zone.parse("2026-07-01") }
      let(:range) { Date.parse("2026-08-01")..Date.parse("2026-08-14") }
      let(:rates) { [rate, second_rate] }
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Time.zone.parse("2026-07-01"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Date.parse("2026-08-06"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end

      it "splits periods at billing boundaries and rate effective dates" do
        expect(result.next_billing_at).to eq(Time.zone.parse("2026-08-17"))
        expect(result.periods.map { [it.period_from, it.period_to, it.rate] }).to eq(
          [
            [Time.zone.parse("2026-07-27"), end_of_day.call("2026-08-02"), rate],
            [Time.zone.parse("2026-08-03"), Time.zone.parse("2026-08-05 23:59:59.999999"), rate],
            [Time.zone.parse("2026-08-06"), end_of_day.call("2026-08-09"), second_rate],
            [Time.zone.parse("2026-08-10"), end_of_day.call("2026-08-16"), second_rate]
          ]
        )
      end
    end

    context "with three rates using different billing intervals" do
      let(:billing_anchor_date) { Date.parse("2026-01-01") }
      let(:started_at) { Time.zone.parse("2026-01-01") }
      let(:range) { Date.parse("2026-01-01")..Date.parse("2026-05-31") }
      let(:rates) { [rate, second_rate, third_rate] }
      let(:rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Time.zone.parse("2026-01-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end
      let(:second_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Time.zone.parse("2026-03-15"),
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end
      let(:third_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Time.zone.parse("2026-05-01"),
          billing_interval_count: 1,
          billing_interval_unit: "month"
        )
      end

      it "uses the interval active at the cycle start while splitting on effective dates" do
        expect(result.next_billing_at).to eq(Time.zone.parse("2026-06-01"))
        expect(result.periods.map { [it.period_from, it.period_to, it.rate] }).to eq(
          [
            [Time.zone.parse("2026-01-01"), end_of_day.call("2026-01-31"), rate],
            [Time.zone.parse("2026-02-01"), end_of_day.call("2026-02-28"), rate],
            [Time.zone.parse("2026-03-01"), Time.zone.parse("2026-03-14 23:59:59.999999"), rate],
            [Time.zone.parse("2026-03-15"), end_of_day.call("2026-03-31"), second_rate],
            [Time.zone.parse("2026-04-01"), end_of_day.call("2026-04-01"), second_rate],
            [Time.zone.parse("2026-04-02"), end_of_day.call("2026-04-08"), second_rate],
            [Time.zone.parse("2026-04-09"), end_of_day.call("2026-04-15"), second_rate],
            [Time.zone.parse("2026-04-16"), end_of_day.call("2026-04-22"), second_rate],
            [Time.zone.parse("2026-04-23"), end_of_day.call("2026-04-29"), second_rate],
            [Time.zone.parse("2026-04-30"), Time.zone.parse("2026-04-30 23:59:59.999999"), second_rate],
            [Time.zone.parse("2026-05-01"), end_of_day.call("2026-05-06"), third_rate],
            [Time.zone.parse("2026-05-07"), end_of_day.call("2026-05-31"), third_rate]
          ]
        )
      end
    end
  end
end
