# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingPeriods::DatesService do
  describe "::Options" do
    it "provides the default date-generation options" do
      expect(described_class::Options.default).to eq(
        described_class::Options.new(
          timezone: "UTC",
          exclude_out_of_range: true,
          realign_billing_anchor: true,
          termination: false
        )
      )
    end
  end

  describe ".from_subscription_rate_card" do
    subject(:result) do
      described_class.from_subscription_rate_card(
        subscription_rate_card,
        rates: rate_card.rates.order(:effective_from),
        rate_phases:,
        range:,
        options:
      )
    end

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:plan) { create(:plan, organization:) }
    let(:subscription) do
      create(
        :subscription,
        customer:,
        organization:,
        plan:,
        started_at: Time.zone.parse("2026-08-03"),
        activated_at: Time.zone.parse("2026-08-03"),
        subscription_at: Time.zone.parse("2026-08-03")
      )
    end
    let(:rate_card) { create(:rate_card, organization:) }
    let(:realign_billing_anchor) { false }
    let(:options) do
      described_class::Options.new(
        timezone: "UTC",
        exclude_out_of_range: true,
        realign_billing_anchor:,
        termination: false
      )
    end
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-08-03"),
        started_at: Time.zone.parse("2026-08-03"),
        next_billing_at: Time.zone.parse("2026-08-03")
      )
    end
    let(:range) { "2026-08-05".."2026-08-17" }
    let(:rate_phases) do
      SubscriptionRateCards::ResolveRatePhasesService.call!(
        subscription_rate_card:,
        plan_rate_cards: plan.applied_rate_cards.to_a
      ).rate_phases
    end
    let!(:intro_phase) do
      create(
        :rate_phase,
        :subscription_level,
        organization:,
        subscription_rate_card:,
        position: 1,
        billing_interval_cycle_count: 1
      )
    end
    let!(:standard_phase) do
      create(
        :rate_phase,
        :subscription_level,
        organization:,
        subscription_rate_card:,
        position: 2,
        billing_interval_cycle_count: nil
      )
    end

    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2026-08-01"),
        billing_interval_unit: "week"
      )
    end
    let(:second_rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        code: "rate_r1_v2",
        effective_from: Time.zone.parse("2026-08-06"),
        billing_interval_unit: "week"
      )
    end

    before do
      rate_card_rate
      second_rate_card_rate
    end

    it "keeps the same cycle window when a rate effective date splits a cycle" do
      expect(result.periods.map(&:period_from)).to eq(
        [
          Time.zone.parse("2026-08-03"),
          Time.zone.parse("2026-08-06"),
          Time.zone.parse("2026-08-10")
        ]
      )
      expect(result.periods.map(&:cycle_index)).to eq([0, 0, 1])
      expect(result.periods.map(&:rate)).to eq([rate_card_rate, second_rate_card_rate, second_rate_card_rate])
      expect(result.periods.map(&:rate_phase)).to eq([intro_phase, intro_phase, standard_phase])
    end

    context "with a terminal phase" do
      let(:range) { "2026-08-24".."2026-09-07" }

      it "keeps using the nil cycle-count phase for later cycles" do
        expect(result.periods.map(&:cycle_index)).to eq([3, 4])
        expect(result.periods.map(&:rate_phase)).to eq([standard_phase, standard_phase])
      end
    end

    context "with an invalid billing timing" do
      before do
        allow(subscription_rate_card.rate_card).to receive(:billing_timing).and_return("invalid")
      end

      it "raises an exception" do
        expect { result }.to raise_error(ArgumentError, "Invalid billing timing: invalid")
      end
    end

    context "with termination mode" do
      let(:range) { Time.zone.parse("2026-08-05")..Time.zone.parse("2026-08-17 12:34:56") }
      let(:options) do
        described_class::Options.new(
          timezone: "UTC",
          exclude_out_of_range: true,
          realign_billing_anchor: false,
          termination: true
        )
      end

      it "returns periods overlapping the range regardless of billing timing and clamps the final period" do
        expect(result.periods.map { [it.period_from, it.period_to] }).to eq(
          [
            [Time.zone.parse("2026-08-03"), Time.zone.parse("2026-08-05 23:59:59.999999")],
            [Time.zone.parse("2026-08-06"), Time.zone.parse("2026-08-09").end_of_day],
            [Time.zone.parse("2026-08-10"), Time.zone.parse("2026-08-16").end_of_day],
            [Time.zone.parse("2026-08-17"), Time.zone.parse("2026-08-17 12:34:56")]
          ]
        )
      end
    end

    context "with plan-level phases" do
      let(:range) { "2026-08-03".."2026-11-10" }
      let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }
      let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "49.00"}) }

      before do
        intro_phase.discard!
        standard_phase.discard!
        create(
          :rate_phase,
          organization:,
          plan_rate_card:,
          code: "negotiated_intro",
          position: 1,
          billing_interval_cycle_count: 3,
          rate_override:
        )
        create(
          :rate_phase,
          organization:,
          plan_rate_card:,
          code: "standard",
          position: 2,
          billing_interval_cycle_count: nil
        )
      end

      it "uses the plan phases for a materialized subscription rate card" do
        periods = result.periods.first(5)

        expect(periods.map(&:cycle_index)).to eq([0, 0, 1, 2, 3])
        expect(periods.map { |period| period.rate_phase&.code }).to eq(
          %w[negotiated_intro negotiated_intro negotiated_intro negotiated_intro standard]
        )
        expect(periods.map(&:rate_override)).to eq([rate_override, rate_override, rate_override, rate_override, nil])
      end
    end

    context "with a phase override interval" do
      let(:range) { "2026-08-16".."2026-08-17" }
      let(:rate_override) do
        create(
          :rate_override,
          organization:,
          billing_interval_count: 2,
          billing_interval_unit: "week"
        )
      end

      before do
        intro_phase.update!(billing_interval_cycle_count: nil, rate_override:)
        standard_phase.discard!
      end

      it "uses the override interval to generate the cycle window" do
        period = result.periods.sole

        expect(period.period_from).to eq(Time.zone.parse("2026-08-06"))
        expect(period.period_to.to_date).to eq(Date.parse("2026-08-16"))
        expect(period.cycle_index).to eq(0)
        expect(period.rate_phase).to eq(intro_phase)
      end
    end

    context "with an override interval followed by a base interval" do
      let(:range) { "2026-08-03".."2026-10-31" }
      let(:rate_override) do
        create(
          :rate_override,
          organization:,
          billing_interval_count: 1,
          billing_interval_unit: "week"
        )
      end

      before do
        rate_card.rates.find_each { |rate| rate.update!(billing_interval_unit: "month") }
        intro_phase.update!(billing_interval_cycle_count: 6, rate_override:)
      end

      it "uses the original anchor by default" do
        period = result.periods.find { |current_period| current_period.cycle_index == 6 }

        expect(period.period_from).to eq(Time.zone.parse("2026-09-14"))
        expect(period.period_to).to eq(Time.zone.parse("2026-10-02").end_of_day)
      end

      context "when realigning the billing anchor" do
        let(:realign_billing_anchor) { true }

        it "continues the base interval from the previous cycle end" do
          period = result.periods.find { |current_period| current_period.cycle_index == 6 }

          expect(period.period_from).to eq(Time.zone.parse("2026-09-14"))
          expect(period.period_to).to eq(Time.zone.parse("2026-10-13").end_of_day)
        end
      end
    end
  end
end
