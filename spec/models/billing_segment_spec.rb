# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegment do
  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription)
      expect(subject).to belong_to(:customer)
      expect(subject).to belong_to(:subscription_rate_card)
      expect(subject).to belong_to(:invoice).optional
      expect(subject).to belong_to(:rate_card_rate).optional
      expect(subject).to belong_to(:rate_override).optional
      expect(subject).to belong_to(:pricing_unit).optional
      expect(described_class.reflect_on_association(:customer).scope).to be_present
      expect(described_class.reflect_on_association(:subscription_rate_card).scope).to be_present
      expect(described_class.reflect_on_association(:rate_card_rate).scope).to be_present
      expect(described_class.reflect_on_association(:rate_override).scope).to be_present
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:billing_at)
      expect(subject).to validate_presence_of(:cycle_started_at)
      expect(subject).to validate_presence_of(:started_at)
      expect(subject).to validate_presence_of(:ended_at)
      expect(subject).to validate_numericality_of(:proration_ratio)
        .is_greater_than_or_equal_to(0)
        .is_less_than_or_equal_to(1)
    end
  end

  # The cycle a segment belongs to. A whole cycle is one segment and the two windows match;
  # a cycle cut by a rate change is several segments sharing the cycle they came from, which
  # is the only thing that groups them — consecutive segments are contiguous, so a rate cut
  # and a cycle boundary are indistinguishable from started_at alone.
  describe "#cycle_started_at" do
    it "matches started_at for a cycle billed whole" do
      segment = create(:billing_segment, cycle_started_at: Time.utc(2026, 9, 1), started_at: Time.utc(2026, 9, 1))

      expect(segment.cycle_started_at).to eq(segment.started_at)
    end

    # Written the way the engine writes them: windows are half-open there and inclusive
    # here, so ended_at sits a microsecond before the next segment opens. The exclusion
    # constraint rejects the naive version, since its range is inclusive at both ends.
    it "groups the segments a rate change cut one cycle into" do
      cycle_started_at = Time.utc(2026, 9, 1)
      cut = Time.utc(2026, 9, 15)
      card = create(:subscription_rate_card)
      attributes = {
        subscription_rate_card: card, organization: card.organization,
        subscription: card.subscription, customer: card.customer, cycle_started_at:
      }
      first = create(:billing_segment, **attributes, started_at: cycle_started_at, ended_at: described_class.inclusive_end(cut))
      second = create(:billing_segment, **attributes, started_at: cut, ended_at: described_class.inclusive_end(Time.utc(2026, 10, 1)))

      expect(described_class.where(subscription_rate_card: card, cycle_started_at:)).to match_array([first, second])
    end
  end

  describe "#rate_properties" do
    subject(:rate_properties) { billing_segment.rate_properties }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, rate_properties: {"amount" => "10.00"}) }
    let(:billing_segment) { described_class.new(rate_card_rate:, rate_properties: {"amount" => "10.00"}) }

    it "returns the stored rate properties" do
      expect(rate_properties).to eq({"amount" => "10.00"})
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, rate_properties: {"amount" => "5.00"}) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:, rate_properties: {"amount" => "5.00"}) }

      it "returns the stored override properties" do
        expect(rate_properties).to eq({"amount" => "5.00"})
      end

      context "when the override changes after scheduling" do
        before { rate_override.rate_properties = {"amount" => "8.00"} }

        it "keeps the stored snapshot" do
          expect(rate_properties).to eq({"amount" => "5.00"})
        end
      end
    end
  end

  describe "#billing_interval" do
    subject(:billing_interval) { billing_segment.billing_interval }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, billing_interval_count: 1, billing_interval_unit: "month") }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate's cadence" do
      expect(billing_interval).to eq(Billing::Interval.new(count: 1, unit: :month))
    end

    context "with a rate override carrying its own cadence" do
      let(:rate_override) { build_stubbed(:rate_override, billing_interval_count: 2, billing_interval_unit: "week") }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override's cadence" do
        expect(billing_interval).to eq(Billing::Interval.new(count: 2, unit: :week))
      end
    end

    # The override's two cadence columns are independently nullable, so a partial override
    # must not leave the interval half-built.
    context "with a rate override that sets no cadence" do
      let(:rate_override) { build_stubbed(:rate_override) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "falls back to the rate's cadence" do
        expect(billing_interval).to eq(Billing::Interval.new(count: 1, unit: :month))
      end
    end
  end

  describe "#pricing_unit_conversion_rate" do
    subject(:pricing_unit_conversion_rate) { billing_segment.pricing_unit_conversion_rate }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, applied_pricing_unit_conversion_rate: 0.5) }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate conversion rate" do
      expect(pricing_unit_conversion_rate).to eq(0.5)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, pricing_unit_conversion_rate: 0.25) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override conversion rate" do
        expect(pricing_unit_conversion_rate).to eq(0.25)
      end
    end
  end

  describe "#min_amount_cents" do
    subject(:min_amount_cents) { billing_segment.min_amount_cents }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, min_amount_cents: 1_000) }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate minimum amount" do
      expect(min_amount_cents).to eq(1_000)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, min_amount_cents: 2_000) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override minimum amount" do
        expect(min_amount_cents).to eq(2_000)
      end
    end
  end
end
