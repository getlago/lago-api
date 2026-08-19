# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ScheduleService do
  describe ".call" do
    subject(:result) { described_class.call(customer:, range:) }

    around do |example|
      travel_to(current_time) { example.run }
    end

    let(:current_time) { Time.zone.parse("2026-08-14 12:00:00") }
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone:) }
    let(:timezone) { "UTC" }
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
    let(:range) { current_time..current_time }
    let(:next_billing_at) { Time.zone.parse("2026-08-01") }
    let(:billing_anchor_date) { Date.parse("2026-01-01") }
    let(:started_at) { Time.zone.parse("2026-01-01") }
    let(:ended_at) { nil }
    let(:billing_interval_count) { 1 }
    let(:billing_interval_unit) { "month" }
    let!(:rate_card_rate) do
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        effective_from: Time.zone.parse("2026-01-01"),
        billing_interval_count:,
        billing_interval_unit:
      )
    end

    before do
      create(
        :subscription_rate_card,
        organization:,
        subscription:,
        customer:,
        rate_card:,
        billing_anchor_date:,
        started_at:,
        next_billing_at:,
        ended_at:
      )
    end

    it "does not schedule periods outside the default scheduling range" do
      expect { result }.not_to change(BillingCycle, :count)

      expect(result.billing_cycles).to eq([])
      expect(customer.subscription_rate_cards.sole.reload.next_billing_at).to eq(Time.zone.parse("2026-08-01"))
    end

    context "with a single-day range overlapping an advance period" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product: fixed_product, proration: true) }
      let(:next_billing_at) { Time.zone.parse("2026-08-01") }

      it "schedules the advance period due for the item" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-01"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-08-31 23:59:59.999999"))
        expect(billing_cycle.billing_at).to eq(current_time)
        expect(billing_cycle.proration_ratio).to eq(1)
        expect(customer.subscription_rate_cards.sole.reload.next_billing_at).to eq(Time.zone.parse("2026-09-01"))
      end
    end

    context "without an explicit range" do
      subject(:result) { described_class.call(customer:) }

      let(:rate_card) { create(:rate_card, :advance, organization:) }
      let(:current_time) { Time.zone.parse("2026-08-11 12:00:00") }
      let(:next_billing_at) { Time.zone.parse("2026-08-10") }
      let(:billing_anchor_date) { Date.parse("2026-09-01") }
      let(:started_at) { Time.zone.parse("2026-08-10") }

      it "starts from the seeded item clock instead of the current day" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-10"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-08-31 23:59:59.999999"))
      end

      context "when the generated advance period starts in the past" do
        let(:current_time) { Time.zone.parse("2026-08-12 12:00:00") }
        let(:next_billing_at) { Time.zone.parse("2026-08-10") }
        let(:billing_anchor_date) { Date.parse("2026-08-20") }
        let(:started_at) { Time.zone.parse("2026-08-10") }

        it "sets billing_at to the scheduling time" do
          expect { result }.to change(BillingCycle, :count).by(1)

          billing_cycle = result.billing_cycles.sole
          expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-10"))
          expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-08-19 23:59:59.999999"))
          expect(billing_cycle.billing_at).to eq(current_time)
        end
      end
    end

    context "when the generated advance period starts in the future" do
      let(:rate_card) { create(:rate_card, :advance, organization:) }
      let(:current_time) { Time.zone.parse("2026-08-12 12:00:00") }
      let(:range) { "2026-08-20".."2026-08-20" }
      let(:next_billing_at) { Time.zone.parse("2026-08-20") }
      let(:billing_anchor_date) { Date.parse("2026-08-20") }
      let(:started_at) { Time.zone.parse("2026-08-10") }

      it "keeps billing_at on the future billing boundary" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-20"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-09-19 23:59:59.999999"))
        expect(billing_cycle.billing_at).to eq(Time.zone.parse("2026-08-20"))
      end
    end

    context "with a closed date range" do
      let(:range) { "2026-07-15".."2026-08-14" }
      let(:next_billing_at) { Time.zone.parse("2026-08-01") }

      it "schedules billing cycles overlapping the range" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-07-01"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-07-31 23:59:59.999999"))
        expect(billing_cycle.billing_at).to eq(current_time)
        expect(billing_cycle.rate_card_rate).to eq(rate_card_rate)
        expect(billing_cycle.rate_override).to be_nil
        expect(customer.subscription_rate_cards.sole.reload.next_billing_at).to eq(Time.zone.parse("2026-09-01"))
      end

      context "with a rate card pricing unit" do
        let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }
        let(:rate_card) { create(:rate_card, organization:, applied_pricing_unit_code: pricing_unit.code) }
        let!(:rate_card_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            effective_from: Time.zone.parse("2026-01-01"),
            billing_interval_count:,
            billing_interval_unit:,
            applied_pricing_unit_conversion_rate: 0.5
          )
        end

        before { pricing_unit }

        it "stores the pricing unit on the billing cycle" do
          expect { result }.to change(BillingCycle, :count).by(1)

          expect(result.billing_cycles.sole.pricing_unit).to eq(pricing_unit)
        end
      end
    end

    context "with rate changes inside the range" do
      let(:range) { "2026-07-01".."2026-09-01" }
      let(:next_billing_at) { Time.zone.parse("2026-08-01") }
      let!(:second_rate_card_rate) do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Time.zone.parse("2026-08-01"),
          rate_properties: {"amount" => "40.00"}
        )
      end

      it "splits billing cycles across rate effective dates and calendar periods" do
        expect { result }.to change(BillingCycle, :count).by(2)

        expect(result.billing_cycles.map { [it.period_from, it.period_to] }).to eq(
          [
            [Time.zone.parse("2026-07-01"), Time.zone.parse("2026-07-31 23:59:59.999999")],
            [Time.zone.parse("2026-08-01"), Time.zone.parse("2026-08-31 23:59:59.999999")]
          ]
        )
        expect(result.billing_cycles.map(&:rate_card_rate)).to eq([rate_card_rate, second_rate_card_rate])
      end
    end

    context "with a phase rate override" do
      let(:range) { "2026-07-15".."2026-08-14" }
      let(:next_billing_at) { Time.zone.parse("2026-08-01") }
      let(:subscription_rate_card) { customer.subscription_rate_cards.sole }
      let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "5.00"}) }

      before do
        create(
          :rate_phase,
          :subscription_level,
          organization:,
          subscription_rate_card:,
          position: 1,
          billing_interval_cycle_count: nil,
          rate_override:
        )
      end

      it "stores the base rate and override on the billing cycle" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.rate_card_rate).to eq(rate_card_rate)
        expect(billing_cycle.rate_override).to eq(rate_override)
        expect(billing_cycle.rate_properties).to eq("amount" => "5.00")
      end
    end

    context "with a rate change in the middle of a weekly period" do
      let(:range) { "2026-08-01".."2026-08-14" }
      let(:next_billing_at) { Time.zone.parse("2026-08-03") }
      let(:billing_anchor_date) { Date.parse("2026-08-03") }
      let(:billing_interval_unit) { "week" }

      before do
        create(
          :rate_card_rate,
          organization:,
          rate_card:,
          code: "rate_r1_v2",
          effective_from: Date.parse("2026-08-06"),
          billing_interval_count:,
          billing_interval_unit:,
          rate_properties: {"amount" => "40.00"}
        )
      end

      it "splits the billing period at the rate effective date" do
        expect { result }.to change(BillingCycle, :count).by(3)

        expect(result.billing_cycles.map { [it.period_from, it.period_to] }).to eq(
          [
            [Time.zone.parse("2026-07-27"), Time.zone.parse("2026-08-02 23:59:59.999999")],
            [Time.zone.parse("2026-08-03"), Time.zone.parse("2026-08-05 23:59:59.999999")],
            [Time.zone.parse("2026-08-06"), Time.zone.parse("2026-08-09 23:59:59.999999")]
          ]
        )
        expect(result.billing_cycles.map(&:proration_ratio)).to eq([1, 1, 1])
      end

      context "with proration enabled" do
        let(:rate_card) { create(:rate_card, organization:, product: fixed_product, proration: true) }

        it "stores the fee proration ratio for each split period" do
          expect { result }.to change(BillingCycle, :count).by(3)

          expect(result.billing_cycles.map(&:proration_ratio)).to eq([
            BigDecimal("1"),
            BigDecimal("0.4285714286"),
            BigDecimal("0.5714285714")
          ])
        end
      end

      context "when an earlier out-of-range period is already persisted" do
        let(:range) { "2026-08-03".."2026-09-08" }

        before do
          create(
            :billing_cycle,
            organization:,
            subscription:,
            customer:,
            subscription_rate_card: customer.subscription_rate_cards.sole,
            rate_card_rate:,
            billing_at: Time.zone.parse("2026-08-03"),
            period_from: Time.zone.parse("2026-07-27"),
            period_to: Time.zone.parse("2026-08-02 23:59:59.999999")
          )
        end

        it "skips the out-of-range period and schedules the overlapping ones" do
          expect { result }.to change(BillingCycle, :count).by(6)

          expect(result).to be_success
          expect(result.billing_cycles.map(&:period_from)).not_to include(Time.zone.parse("2026-07-27"))
          expect(result.billing_cycles.first.period_from).to eq(Time.zone.parse("2026-08-03"))
        end
      end
    end

    context "with a partial date range inside the current billing period" do
      let(:range) { "2026-08-10".."2026-08-15" }
      let(:next_billing_at) { Time.zone.parse("2026-09-10") }
      let(:billing_anchor_date) { Date.parse("2026-08-10") }
      let(:started_at) { Time.zone.parse("2026-08-10") }

      it "does not schedule the previous arrears period before the subscription rate card starts" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result.billing_cycles).to eq([])
      end
    end

    context "with a partial date range starting before the subscription rate card" do
      let(:range) { "2026-08-01".."2026-08-15" }
      let(:next_billing_at) { Time.zone.parse("2026-09-10") }
      let(:billing_anchor_date) { Date.parse("2026-08-10") }
      let(:started_at) { Time.zone.parse("2026-08-10 12:34:56") }

      it "does not schedule the previous arrears period before the subscription rate card starts" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result.billing_cycles).to eq([])
      end
    end

    context "when the range overlaps the period before the next billing date" do
      let(:range) { "2026-07-31".."2026-08-14" }

      it "schedules the previous period" do
        expect { result }.to change(BillingCycle, :count).by(1)

        billing_cycle = result.billing_cycles.sole
        expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-07-01"))
        expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-07-31 23:59:59.999999"))
        expect(billing_cycle.billing_at).to eq(current_time)
      end
    end

    context "with an ended item overlapping the range" do
      let(:ended_at) { Time.zone.parse("2026-08-07") }
      let(:range) { Time.zone.parse("2026-07-15")..ended_at }
      let(:next_billing_at) { Time.zone.parse("2026-09-01") }

      it "does not schedule a terminating period" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result.billing_cycles).to eq([])
      end
    end

    context "with an ended item outside the range" do
      let(:ended_at) { Time.zone.parse("2026-08-07") }

      it "keeps the previous due item behavior" do
        expect { result }.not_to change(BillingCycle, :count)
        expect(result.billing_cycles).to eq([])
      end
    end

    context "when a single-day range includes the next billing date" do
      let(:current_time) { Time.zone.parse("2026-09-10 12:00:00") }
      let(:next_billing_at) { Time.zone.parse("2026-09-10") }
      let(:billing_anchor_date) { Date.parse("2026-08-10") }
      let(:started_at) { Time.zone.parse("2026-08-10 12:34:56") }

      it "does not schedule the closed arrears period outside the range" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result.billing_cycles).to eq([])
        expect(customer.subscription_rate_cards.sole.reload.next_billing_at).to eq(Time.zone.parse("2026-09-10"))
      end

      context "with a customer timezone" do
        let(:timezone) { "Europe/Paris" }

        it "does not schedule the closed arrears period outside the range" do
          expect { result }.not_to change(BillingCycle, :count)

          expect(result.billing_cycles).to eq([])
          expect(customer.subscription_rate_cards.sole.reload.next_billing_at).to eq(Time.zone.parse("2026-09-10"))
        end
      end

      context "with a two-day lookback range" do
        let(:range) { "2026-09-09".."2026-09-10" }

        it "schedules the closed arrears period overlapping the range" do
          expect { result }.to change(BillingCycle, :count).by(1)

          billing_cycle = result.billing_cycles.sole
          expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-10"))
          expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-09-09 23:59:59.999999"))
          expect(billing_cycle.billing_at).to eq(current_time)
          expect(billing_cycle.subscription_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-10"))
        end

        context "with a customer timezone" do
          let(:timezone) { "Europe/Paris" }

          it "floors the subscription rate card start in the customer timezone" do
            expect { result }.to change(BillingCycle, :count).by(1)

            billing_cycle = result.billing_cycles.sole
            expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-08-09 22:00:00"))
            expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-09-09 21:59:59.999999"))
            expect(billing_cycle.subscription_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-09 22:00:00"))
          end
        end
      end

      context "with an advance rate card" do
        let(:rate_card) { create(:rate_card, :advance, organization:) }

        it "schedules the full advance period due on the requested day" do
          expect { result }.to change(BillingCycle, :count).by(1)

          billing_cycle = result.billing_cycles.sole
          expect(billing_cycle.period_from).to eq(Time.zone.parse("2026-09-10"))
          expect(billing_cycle.period_to).to eq(Time.zone.parse("2026-10-09 23:59:59.999999"))
          expect(billing_cycle.billing_at).to eq(current_time)
          expect(billing_cycle.subscription_rate_card.reload.next_billing_at).to eq(Time.zone.parse("2026-10-10"))
        end
      end
    end

    context "when different subscription rate cards have overlapping periods" do
      let(:range) { "2026-07-15".."2026-08-14" }
      let(:second_rate_card) { create(:rate_card, organization:) }

      before do
        create(:rate_card_rate, organization:, rate_card: second_rate_card, effective_from: Time.zone.parse("2026-01-01"))
        create(
          :subscription_rate_card,
          organization:,
          subscription:,
          customer:,
          rate_card: second_rate_card,
          billing_anchor_date: Date.parse("2026-01-01"),
          started_at: Time.zone.parse("2026-01-01"),
          next_billing_at: Time.zone.parse("2026-08-01")
        )
      end

      it "schedules every billing cycle" do
        expect { result }.to change(BillingCycle, :count).by(2)

        expect(result).to be_success
        expect(result.billing_cycles.map(&:subscription_rate_card_id).uniq.count).to eq(2)
      end
    end

    context "when a persisted billing cycle overlaps the generated period" do
      let(:range) { "2026-07-15".."2026-08-14" }

      before do
        create(
          :billing_cycle,
          organization:,
          subscription:,
          customer:,
          subscription_rate_card: customer.subscription_rate_cards.sole,
          rate_card_rate:,
          billing_at: Time.zone.parse("2026-08-15"),
          period_from: Time.zone.parse("2026-07-15"),
          period_to: Time.zone.parse("2026-08-15 23:59:59.999999")
        )
      end

      it "returns an error and does not persist the generated billing cycle" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result).to be_failure
        expect(result.billing_cycles).to eq([])
        expect(result.error.messages).to eq(billing_cycle: ["overlapping_periods"])
      end
    end

    context "when the generated billing cycle already exists" do
      let(:range) { "2026-07-15".."2026-08-14" }

      before do
        create(
          :billing_cycle,
          organization:,
          subscription:,
          customer:,
          subscription_rate_card: customer.subscription_rate_cards.sole,
          rate_card_rate:,
          billing_at: Time.zone.parse("2026-08-14"),
          period_from: Time.zone.parse("2026-07-01"),
          period_to: Time.zone.parse("2026-07-31 23:59:59.999999")
        )
      end

      it "returns an error and does not persist a duplicate billing cycle" do
        expect { result }.not_to change(BillingCycle, :count)

        expect(result).to be_failure
        expect(result.billing_cycles).to eq([])
        expect(result.error.messages).to eq(billing_cycle: ["overlapping_periods"])
      end
    end
  end
end
