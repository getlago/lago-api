# frozen_string_literal: true

require "rails_helper"

# The producer side of a pay-in-advance increase. Sequence from
# fixed-charge-pay-in-advance.md, standard prorated: 1 -> 3 -> 5 -> 1 -> 2.
RSpec.describe BillingCycles::ScheduleAdvanceIncrementService do
  subject(:result) { described_class.call(subscription_rate_card: card, at:) }

  let(:organization) { create(:organization, timezone: "UTC") }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, *traits, organization:, product:, currency: "USD") }
  let(:traits) { [:advance] }
  let(:period_to) { Time.utc(2025, 5, 31).end_of_day }

  let(:card) { version(3, 2) }
  let(:at) { Time.utc(2025, 5, 2) }

  let(:rate_card_rate) do
    create(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "31"})
  end

  # What has already been invoiced when the change arrives. Contexts override it to describe
  # a different history.
  def bill_opening
    cycle_for(version(1, 1, 2), 1, 1)
  end

  before { bill_opening }

  def version(units, from_day, to_day = nil)
    create(
      :subscription_rate_card,
      organization:, subscription:, customer:, rate_card:, units:,
      started_at: Time.utc(2025, 5, from_day),
      ended_at: to_day && Time.utc(2025, 5, to_day),
      billing_anchor_date: Date.new(2025, 5, 1),
      next_billing_at: Time.utc(2025, 6, 1)
    )
  end

  def cycle_for(version_card, from_day, ratio, ends: period_to)
    create(
      :billing_cycle,
      organization:, subscription:, customer:,
      subscription_rate_card: version_card,
      rate_card_rate:,
      rate_properties: rate_card_rate.rate_properties,
      proration_ratio: ratio,
      period_from: Time.utc(2025, 5, from_day),
      period_to: ends,
      billing_at: Time.utc(2025, 5, from_day)
    )
  end

  it "schedules the remaining window with the share of the period still ahead" do
    expect(result.billing_cycle).to be_present
    expect(result.billing_cycle.period_from).to eq(at)
    expect(result.billing_cycle.period_to).to be_within(1.second).of(period_to)
    expect(result.billing_cycle.proration_ratio).to eq((BigDecimal(30) / 31).round(10))
    expect(result.billing_cycle.subscription_rate_card).to eq(card)
  end

  it "prices to $60.00 through the ordinary path" do
    fee = BillingCycles::Fees::ComputeService.call!(billing_cycle: result.billing_cycle).fee

    expect(fee.amount_cents).to eq(6_000)
    expect(fee.units).to eq(2)
  end

  # The clock stays on the next period: making the successor due would regenerate the whole
  # period and bill May a second time.
  it "leaves the billing clock alone" do
    expect { result }.not_to change { card.reload.next_billing_at }
  end

  context "when the quantity falls" do
    let(:card) { version(1, 2) }

    it "schedules nothing and never refunds" do
      expect(result.billing_cycle).to be_nil
      expect(BillingCycle.count).to eq(1)
    end
  end

  context "when the quantity rises but stays under the watermark" do
    let(:card) { version(2, 3) }
    let(:at) { Time.utc(2025, 5, 3) }

    def bill_opening
      cycle_for(version(1, 1, 2), 1, 1)
      cycle_for(version(5, 2, 3), 2, BigDecimal(30) / 31)
    end

    it "schedules nothing — that coverage is already paid for" do
      expect(result.billing_cycle).to be_nil
    end
  end

  context "when nothing has been billed for the period yet" do
    def bill_opening
      nil
    end

    it "leaves it to the ordinary producer" do
      expect(result.billing_cycle).to be_nil
    end
  end

  context "when the card is billed in arrears" do
    let(:traits) { [] }

    it "schedules nothing — the period-end cycle absorbs the change" do
      expect(result.billing_cycle).to be_nil
    end
  end

  # A rate change splits the period into segments invoiced separately. An increase belongs to
  # the segment it lands in, and its ratio stays denominated in the full period.
  context "when a rate change split the period" do
    let(:segment_end) { Time.utc(2025, 5, 14).end_of_day }
    let(:card) { version(3, 3) }
    let(:at) { Time.utc(2025, 5, 3) }

    def bill_opening
      cycle_for(version(1, 1, 3), 1, BigDecimal(14) / 31, ends: segment_end)
    end

    it "schedules the rest of that segment only" do
      expect(result.billing_cycle.period_to).to be_within(1.second).of(segment_end)
      expect(result.billing_cycle.proration_ratio).to eq((BigDecimal(12) / 31).round(10))
    end
  end
end
