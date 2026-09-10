# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegment do
  subject(:billing_segment) { build(:billing_segment) }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_prefix(:status)
        .with_values(pending: "pending", processing: "processing", done: "done", failed: "failed")
    end
  end

  describe "associations" do
    it do
      expect(billing_segment).to belong_to(:organization)
      expect(billing_segment).to belong_to(:contract)
      expect(billing_segment).to belong_to(:customer)
      expect(billing_segment).to belong_to(:contract_rate_card)
      expect(billing_segment).to belong_to(:invoice).optional
      expect(billing_segment).to belong_to(:rate_card_rate).optional
      expect(billing_segment).to belong_to(:rate_override).optional
      expect(billing_segment).to belong_to(:pricing_unit).optional
      expect(described_class.reflect_on_association(:customer).scope).to be_present
      expect(described_class.reflect_on_association(:contract_rate_card).scope).to be_present
      expect(described_class.reflect_on_association(:rate_card_rate).scope).to be_present
      expect(described_class.reflect_on_association(:rate_override).scope).to be_present
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:billing_at)
      expect(subject).to validate_presence_of(:cycle_started_at)
      expect(subject).to validate_presence_of(:currency)
      expect(subject).to validate_inclusion_of(:currency).in_array(described_class.currency_list)
      expect(subject).to validate_presence_of(:started_at)
      expect(subject).to validate_presence_of(:ended_at)
      expect(subject).to validate_numericality_of(:proration_ratio)
        .is_greater_than_or_equal_to(0)
        .is_less_than_or_equal_to(1)
    end

    describe "rate validation" do
      it "requires a rate card rate or a rate override" do
        segment = build(:billing_segment, rate_card_rate: nil, rate_override: nil)

        expect(segment).not_to be_valid
        expect(segment.errors.where(:base, :rate_card_rate_or_rate_override_required)).to be_present
      end

      it "accepts a rate override without a rate card rate" do
        segment = build(:billing_segment, rate_card_rate: nil, rate_override: build(:rate_override))

        expect(segment).to be_valid
      end
    end

    describe "period bounds validation" do
      it "rejects a period ending before it starts" do
        segment = build(:billing_segment, started_at: Time.zone.parse("2026-09-15"), ended_at: Time.zone.parse("2026-09-01"))

        expect(segment).not_to be_valid
        expect(segment.errors.where(:ended_at, :must_be_after_started_at)).to be_present
      end
    end

    describe "cycle bounds validation" do
      it "rejects a cycle opening after the segment starts" do
        segment = build(:billing_segment, cycle_started_at: Time.zone.parse("2026-09-15"), started_at: Time.zone.parse("2026-09-01"))

        expect(segment).not_to be_valid
        expect(segment.errors.where(:cycle_started_at, :must_be_before_started_at)).to be_present
      end
    end
  end

  describe "#rate" do
    let(:rate_card_rate) { build_stubbed(:rate_card_rate) }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate card rate" do
      expect(billing_segment.rate).to eq(rate_card_rate)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override" do
        expect(billing_segment.rate).to eq(rate_override)
      end
    end
  end

  describe "#duration_in_days" do
    subject(:segment) { described_class.new(customer:, started_at:, ended_at:) }

    let(:timezone) { "UTC" }
    let(:customer) { build(:customer, timezone:) }
    let(:started_at) { Time.zone.parse("2026-09-01") }
    let(:ended_at) { Time.zone.parse("2026-09-30").end_of_day }

    it "returns the inclusive segment duration" do
      expect(segment.duration_in_days).to eq(30)
    end

    context "with a mid-day rate change" do
      let(:cut) { Time.zone.parse("2026-06-16 09:30:00") }

      context "when before the change" do
        let(:started_at) { Time.zone.parse("2026-06-01") }
        let(:ended_at) { described_class.inclusive_end(cut) }

        it "includes the split day containing its midnight" do
          expect(segment.duration_in_days).to eq(16)
        end
      end

      context "when after the change" do
        let(:started_at) { cut }
        let(:ended_at) { described_class.inclusive_end(Time.zone.parse("2026-07-01")) }

        it "excludes the split day assigned to the previous segment" do
          expect(segment.duration_in_days).to eq(14)
        end
      end
    end

    context "with daylight saving time" do
      let(:timezone) { "Europe/Paris" }
      let(:zone) { ActiveSupport::TimeZone[timezone] }
      let(:started_at) { zone.parse("2026-03-01") }
      let(:ended_at) { described_class.inclusive_end(zone.parse("2026-04-01")) }

      it "counts local midnights across daylight saving time" do
        expect(segment.duration_in_days).to eq(31)
      end
    end

    context "with a non-UTC customer timezone" do
      let(:timezone) { "Asia/Tokyo" }
      let(:started_at) { Time.zone.parse("2026-08-31 15:00:00") }
      let(:ended_at) { Time.zone.parse("2026-09-30 14:59:59") }

      it "counts days in the customer timezone" do
        expect(segment.duration_in_days).to eq(30)
      end
    end
  end

  describe "#elapsed_period_ratio" do
    subject(:segment) do
      described_class.new(customer:, started_at:, ended_at:, proration_ratio: 0.5,
        cycle_started_at: Time.utc(2026, 8, 1))
    end

    let(:customer) { build(:customer, timezone: "UTC") }
    let(:started_at) { Time.utc(2026, 8, 20) }
    let(:ended_at) { Time.utc(2026, 8, 29).end_of_day }

    it "measures the segment's elapsed progress independently of service proration and cycle start" do
      expect(segment.elapsed_period_ratio(at: Time.utc(2026, 8, 21))).to eq(2.fdiv(10))
      expect(segment.proration_ratio).to eq(0.5)
    end

    it "defaults to the current time without caching progress" do
      travel_to(Time.utc(2026, 8, 21)) { expect(segment.elapsed_period_ratio).to eq(2.fdiv(10)) }
      travel_to(Time.utc(2026, 8, 29)) { expect(segment.elapsed_period_ratio).to eq(1.0) }
    end

    context "with a non-UTC customer timezone" do
      let(:customer) { build(:customer, timezone: "America/New_York") }
      let(:started_at) { Time.utc(2026, 8, 1, 4) }
      let(:ended_at) { described_class.inclusive_end(Time.utc(2026, 9, 1, 4)) }

      it "uses the customer's date before treating the last day as complete" do
        expect(segment.elapsed_period_ratio(at: Time.utc(2026, 8, 31, 2))).to eq(30.fdiv(31))
      end
    end

    context "with a daylight saving time transition" do
      let(:customer) { build(:customer, timezone: "Europe/Paris") }
      let(:started_at) { Time.utc(2026, 2, 28, 23) }
      let(:ended_at) { described_class.inclusive_end(Time.utc(2026, 3, 31, 22)) }

      it "counts calendar days rather than hours" do
        expect(segment.elapsed_period_ratio(at: Time.utc(2026, 3, 29, 22))).to eq(30.fdiv(31))
      end
    end
  end

  describe "#rate_properties" do
    let(:rate_card_rate) { build_stubbed(:rate_card_rate, rate_properties: {"amount" => "10.00"}) }
    let(:billing_segment) { described_class.new(rate_card_rate:, rate_properties: {"amount" => "10.00"}) }

    it "returns the stored rate properties" do
      expect(billing_segment.rate_properties).to eq("amount" => "10.00")
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, rate_properties: {"amount" => "5.00"}) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:, rate_properties: {"amount" => "5.00"}) }

      it "keeps the stored snapshot" do
        rate_override.rate_properties = {"amount" => "8.00"}

        expect(billing_segment.rate_properties).to eq("amount" => "5.00")
      end
    end
  end

  describe "#currency" do
    it "returns the rate card currency" do
      segment = described_class.new(currency: "EUR")

      expect(segment.currency).to eq("EUR")
    end
  end

  describe "#pricing_unit_conversion_rate" do
    let(:rate_card_rate) { build_stubbed(:rate_card_rate, applied_pricing_unit_conversion_rate: 0.5) }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate conversion rate" do
      expect(billing_segment.pricing_unit_conversion_rate).to eq(0.5)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, pricing_unit_conversion_rate: 0.25) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override conversion rate" do
        expect(billing_segment.pricing_unit_conversion_rate).to eq(0.25)
      end
    end
  end

  describe "#min_amount_cents" do
    let(:rate_card_rate) { build_stubbed(:rate_card_rate, min_amount_cents: 1_000) }
    let(:billing_segment) { described_class.new(rate_card_rate:) }

    it "returns the rate minimum amount" do
      expect(billing_segment.min_amount_cents).to eq(1_000)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, min_amount_cents: 2_000) }
      let(:billing_segment) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override minimum amount" do
        expect(billing_segment.min_amount_cents).to eq(2_000)
      end
    end
  end

  describe "#prorated_min_amount_cents" do
    let(:rate_card_rate) { build_stubbed(:rate_card_rate, min_amount_cents: 1_001, applied_pricing_unit_conversion_rate: 0.5) }
    let(:billing_segment) { described_class.new(rate_card_rate:, currency: "USD", proration_ratio: 0.5) }

    it "prorates the fiat minimum without rounding fractional cents" do
      expect(billing_segment.prorated_min_amount_cents).to eq(BigDecimal("500.5"))
    end

    it "preserves a zero minimum" do
      rate_card_rate.min_amount_cents = 0

      expect(billing_segment.prorated_min_amount_cents).to eq(0)
    end

    context "with a pricing unit" do
      before { billing_segment.pricing_unit = build_stubbed(:pricing_unit) }

      it "converts the prorated fiat minimum into pricing-unit cents" do
        expect(billing_segment.prorated_min_amount_cents).to eq(1_001)
      end

      it "uses the fiat currency subunit factor" do
        billing_segment.currency = "JPY"

        expect(billing_segment.prorated_min_amount_cents).to eq(100_100)
      end

      it "uses the override minimum and conversion rate" do
        billing_segment.rate_override = build_stubbed(:rate_override, min_amount_cents: 2_001, pricing_unit_conversion_rate: 0.25)

        expect(billing_segment.prorated_min_amount_cents).to eq(4_002)
      end
    end
  end

  describe "#cycle_started_at" do
    it "groups segments created by one cycle" do
      cycle_started_at = Time.zone.parse("2026-09-01")
      cut = Time.zone.parse("2026-09-15")
      contract_rate_card = create(:contract_rate_card)
      attributes = {
        organization: contract_rate_card.organization,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        rate_card_rate: create(:rate_card_rate, organization: contract_rate_card.organization, rate_card: contract_rate_card.rate_card),
        cycle_started_at:
      }
      first = create(:billing_segment, **attributes, started_at: cycle_started_at, ended_at: described_class.inclusive_end(cut))
      second = create(:billing_segment, **attributes, started_at: cut, ended_at: described_class.inclusive_end(Time.zone.parse("2026-10-01")))

      expect(described_class.where(contract_rate_card:, cycle_started_at:)).to match_array([first, second])
    end
  end
end
