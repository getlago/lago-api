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

    it "terminates the rate card and creates a pending billing cycle" do
      expect { result }.to change(BillingCycle, :count).by(1)

      expect(result).to be_success
      expect(result.billing_cycles).to be_present
      expect(subscription_rate_card.reload.ended_at).to eq(terminated_at)
      expect(subscription_rate_card.next_billing_at).to eq(terminated_at)

      billing_cycle = result.billing_cycles.sole
      expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-01"))
      # The real termination instant, not the end of its day: these columns are the service
      # boundaries usage metering reads. The termination day being paid for lives in
      # proration_ratio, not here.
      expect(billing_cycle.period_to).to eq(terminated_at)
      expect(billing_cycle.billing_at).to eq(terminated_at)
      expect(billing_cycle.proration_ratio).to eq(1)
      expect(billing_cycle.status).to eq("pending")
    end

    context "with proration enabled" do
      let(:rate_card) { create(:rate_card, organization:, product: fixed_product, proration: true) }

      it "stores the final cycle proration ratio" do
        expect { result }.to change(BillingCycle, :count).by(1)

        expect(result.billing_cycles.sole.proration_ratio).to eq(BigDecimal("0.5483870968"))
      end
    end

    # These pin the two halves of the rule together, because they are easy to conflate:
    #
    #   the WINDOW is the real termination instant   — a fact about service, read by metering
    #   the RATIO counts the termination day whole   — a decision about billing
    #
    # And the property that makes the rule a rule: the TIME of day never changes the ratio.
    # If 00:00 and 23:59 of one day ever prorate differently, it is being applied somewhere
    # other than Billing::TerminationDay.
    context "with the rule that a day entered is a day paid for" do
      # A fixed product carries no billable metric, which is what lets proration be turned on.
      let(:rate_card) { create(:rate_card, organization:, product: fixed_product, proration: true) }

      def cycle_terminated_at(instant)
        described_class.call(subscription_rate_card:, terminated_at: Time.zone.parse(instant)).billing_cycles.sole
      end

      it "prorates the whole day when terminating on its first instant" do
        cycle = cycle_terminated_at("2026-08-17 00:00:00")

        expect(cycle.period_to).to eq(Time.zone.parse("2026-08-17 00:00:00"))
        expect(cycle.proration_ratio).to eq((BigDecimal("17") / 31).round(10))
      end

      it "prorates the same day, and no more, when terminating on its last instant" do
        cycle = cycle_terminated_at("2026-08-17 23:59:00")

        expect(cycle.period_to).to eq(Time.zone.parse("2026-08-17 23:59:00"))
        expect(cycle.proration_ratio).to eq((BigDecimal("17") / 31).round(10))
      end

      it "prorates one day more when terminating on the first instant of the next day" do
        cycle = cycle_terminated_at("2026-08-18 00:00:00")

        expect(cycle.proration_ratio).to eq((BigDecimal("18") / 31).round(10))
      end
    end

    context "when the customer is not in UTC" do
      let(:customer) { create(:customer, organization:, timezone: "America/New_York") }

      let(:rate_card) { create(:rate_card, organization:, product: fixed_product, proration: true) }

      # 2026-09-26T02:00Z is 2026-09-25 22:00 in New York, so the day entered is the 25th
      # and the ratio counts through the 25th THERE. Reading the day in UTC would charge a
      # day the customer never entered.
      it "prorates through the end of the day where the customer is" do
        cycle = described_class.call(subscription_rate_card:, terminated_at: Time.zone.parse("2026-09-26 02:00:00")).billing_cycles.last

        expect(cycle.period_to).to eq(Time.zone.parse("2026-09-26 02:00:00"))
        expect(cycle.proration_ratio).to eq((BigDecimal("25") / 30).round(10))
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

      it "creates billing cycles overlapping now through the termination date" do
        expect { result }.to change(BillingCycle, :count).by(3)

        expect(result.billing_cycles.map { [it.period_from, it.period_to] }).to eq(
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

      it "terminates the rate card without creating billing cycles inline" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result).to be_success
        expect(result.billing_cycles).to eq([])
        expect(subscription_rate_card.reload.ended_at).to eq(terminated_at)
        expect(subscription_rate_card.next_billing_at).to eq(Time.zone.parse("2026-08-01"))
      end
    end
  end
end
