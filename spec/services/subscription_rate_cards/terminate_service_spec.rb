# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCards::TerminateService do
  describe ".call" do
    subject(:result) { described_class.call(subscription_rate_card:, terminated_at:) }

    let(:terminated_at) { Time.zone.parse("2026-08-17 12:34:56") }
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:) }
    let(:fixed_product) { create(:product, :fixed, organization:) }
    let(:subscription) do
      create(
        :subscription,
        customer:,
        organization:,
        plan:,
        started_at: Time.zone.parse("2026-01-01"),
        activated_at: Time.zone.parse("2026-01-01"),
        subscription_at: Time.zone.parse("2026-01-01")
      )
    end
    let(:rate_card) { create(:rate_card, organization:) }
    let(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2026-01-01")
      )
    end
    let(:subscription_rate_card) do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date: Date.parse("2026-01-01"),
        started_at: Time.zone.parse("2026-01-01"),
        next_billing_at: Time.zone.parse("2026-09-01")
      )
    end

    before do
      rate_card_rate
    end

    it "terminates the rate card and creates a pending billing segment" do
      expect { result }.to change(BillingSegment, :count).by(1)

      expect(result).to be_success
      expect(result.billing_segments).to be_present
      expect(subscription_rate_card.reload.ended_at).to eq(terminated_at)
      expect(subscription_rate_card.next_billing_at).to eq(terminated_at)

      billing_segment = result.billing_segments.sole
      expect(billing_segment.period_from).to eq(Time.zone.parse("2026-08-01"))
      expect(billing_segment.period_to).to eq(terminated_at)
      expect(billing_segment.billing_at).to eq(terminated_at)
      expect(billing_segment.proration_ratio).to eq(1)
      expect(billing_segment.status).to eq("pending")
    end

    context "with proration enabled" do
      let(:rate_card) { create(:rate_card, organization:, product: fixed_product, proration: true) }

      it "stores the final cycle proration ratio" do
        expect { result }.to change(BillingSegment, :count).by(1)

        expect(result.billing_segments.sole.proration_ratio).to eq(BigDecimal("0.5483870968"))
      end
    end

    # The fee amounts read the unit back off the row, so a final segment without it would
    # convert at the wrong rate.
    context "with a rate card priced in a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }
      let(:rate_card) do
        create(:rate_card, organization:, applied_pricing_unit_code: pricing_unit.code)
      end
      let(:rate_card_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          effective_from: Time.zone.parse("2026-01-01"),
          applied_pricing_unit_conversion_rate: 0.5
        )
      end

      before { pricing_unit }

      it "carries the pricing unit onto the final segment" do
        expect(result.billing_segments.sole.pricing_unit).to eq(pricing_unit)
      end
    end

    context "with a future termination date" do
      around do |example|
        travel_to(Time.zone.parse("2026-08-17 12:00:00")) { example.run }
      end

      let(:terminated_at) { Time.zone.parse("2026-10-10 12:34:56") }
      let(:subscription_rate_card) do
        create(
          :subscription_rate_card,
          organization:,
          subscription:,
          customer:,
          rate_card:,
          billing_anchor_date: Date.parse("2026-01-01"),
          started_at: Time.zone.parse("2026-01-01"),
          next_billing_at: Time.zone.parse("2026-09-01")
        )
      end

      it "creates billing segments overlapping now through the termination date" do
        expect { result }.to change(BillingSegment, :count).by(3)

        expect(result.billing_segments.map { [it.period_from, it.period_to] }).to eq(
          [
            [Time.zone.parse("2026-08-01"), Time.zone.parse("2026-08-31 23:59:59.999999")],
            [Time.zone.parse("2026-09-01"), Time.zone.parse("2026-09-30 23:59:59.999999")],
            [Time.zone.parse("2026-10-01"), terminated_at]
          ]
        )
      end
    end

    context "with an advance rate card" do
      let(:rate_card) { create(:rate_card, :advance, organization:) }
      let(:subscription_rate_card) do
        create(
          :subscription_rate_card,
          organization:,
          subscription:,
          customer:,
          rate_card:,
          billing_anchor_date: Date.parse("2026-01-01"),
          started_at: Time.zone.parse("2026-01-01"),
          next_billing_at: Time.zone.parse("2026-08-01")
        )
      end

      it "terminates the rate card without creating billing segments inline" do
        expect { result }.not_to change(BillingSegment, :count)

        expect(result).to be_success
        expect(result.billing_segments).to eq([])
        expect(subscription_rate_card.reload.ended_at).to eq(terminated_at)
        expect(subscription_rate_card.next_billing_at).to eq(Time.zone.parse("2026-08-01"))
      end
    end
  end
end
