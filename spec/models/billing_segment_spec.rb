# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegment do
  describe "construction" do
    it "matches the legacy decimal column coercion for a schedule Float" do
      ratio = 20.fdiv(30)
      legacy_ratio = LegacyBillingSegment.new(proration_ratio: ratio).proration_ratio
      segment = described_class.new(proration_ratio: ratio)

      expect(legacy_ratio).to eq(BigDecimal("0.6666666667"))
      expect(segment.proration_ratio).to eq(legacy_ratio)
    end

    it "applies the legacy decimal column coercion to later assignments" do
      ratio = 20.fdiv(30)
      legacy_ratio = LegacyBillingSegment.new(proration_ratio: ratio).proration_ratio
      segment = described_class.new

      segment.proration_ratio = ratio

      expect(segment.proration_ratio).to eq(legacy_ratio)
    end

    it "retains association objects, named values, and serializable association ids without persistence" do
      contract_rate_card = build(:contract_rate_card)
      rate = build(:rate_card_rate, rate_card: contract_rate_card.rate_card)
      segment = build(:billing_segment, organization: contract_rate_card.organization,
        customer: contract_rate_card.contract.customer, contract: contract_rate_card.contract,
        contract_rate_card:, rate_card_rate: rate)

      expect(segment).to have_attributes(
        organization: contract_rate_card.organization,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        billable_metric_code: contract_rate_card.rate_card.product.billable_metric&.code,
        rate_card_rate: rate,
        rate_card_rate_id: rate.id,
        currency: contract_rate_card.rate_card.currency
      )
      expect(segment.attributes).to include("rate_card_rate_id" => rate.id, "started_at" => segment.started_at)
      expect(segment).not_to respond_to(:save, :reload, :persisted?)
    end
  end

  describe ".from_attributes" do
    let(:contract) { create(:contract) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:organization) { contract.organization }
    let(:customer) { contract.customer }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
    let(:rate_override) { create(:rate_override, organization:) }
    let(:pricing_unit) { create(:pricing_unit, organization:) }
    let(:other_contract_organization) { create(:organization) }
    let(:other_rate_override_organization) { create(:organization) }
    let(:other_contract) { create(:contract, organization: other_contract_organization) }
    let(:other_rate_override) { create(:rate_override, organization: other_rate_override_organization) }
    let(:attributes) do
      {
        "organization_id" => organization.id,
        "customer_id" => customer.id,
        "contract_id" => contract_rate_card.contract_id,
        "contract_rate_card_id" => contract_rate_card.id,
        "rate_card_rate_id" => rate_card_rate.id,
        "rate_override_id" => rate_override.id,
        "pricing_unit_id" => pricing_unit.id,
        "rate_properties" => {"amount" => "12.50"},
        "currency" => "USD",
        "proration_ratio" => "0.3750000000",
        "billable_metric_code" => "captured_metric"
      }
    end

    it "hydrates a non-persisted segment and preserves captured values and association ids" do
      segment = described_class.from_attributes(attributes)

      expect(segment).to have_attributes(
        organization:, customer:, contract: contract_rate_card.contract, contract_rate_card:,
        rate_card_rate:, rate_override:, pricing_unit:, rate_properties: {"amount" => "12.50"},
        currency: "USD", proration_ratio: BigDecimal("0.3750000000"), billable_metric_code: "captured_metric",
        rate_card_rate_id: rate_card_rate.id, rate_override_id: rate_override.id, pricing_unit_id: pricing_unit.id
      )
      expect(segment).not_to respond_to(:save, :reload, :persisted?)
    end

    it "accepts symbol keys without mutating the input and hydrates absent optional associations as nil" do
      attributes = self.attributes.symbolize_keys
      attributes.merge!(rate_card_rate_id: nil, rate_override_id: nil, pricing_unit_id: nil)
      original_attributes = attributes.deep_dup

      segment = described_class.from_attributes(attributes)

      expect(attributes).to eq(original_attributes)
      expect(segment).to have_attributes(rate_card_rate: nil, rate_override: nil, pricing_unit: nil)
    end

    it "falls back to the related metric code for legacy attributes without a captured code" do
      attributes = self.attributes.except("billable_metric_code")

      segment = described_class.from_attributes(attributes)

      expect(segment.billable_metric_code).to eq(contract_rate_card.rate_card.product.billable_metric&.code)
    end

    it "rejects associations outside the organization and missing required keys" do
      attributes = self.attributes.merge("contract_id" => other_contract.id)

      expect { described_class.from_attributes(attributes) }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.from_attributes(self.attributes.except("customer_id")) }.to raise_error(KeyError)
    end

    it "rejects a rate override from another organization" do
      expect { described_class.from_attributes(attributes.merge("rate_override_id" => other_rate_override.id)) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "pricing and period helpers" do
    describe "#duration_in_days" do
      it "uses inclusive end semantics and customer timezone" do
        customer = build(:customer, timezone: "Europe/Paris")
        segment = described_class.new(customer:, started_at: Time.utc(2026, 2, 28, 23),
          ended_at: described_class.inclusive_end(Time.utc(2026, 3, 31, 22)))

        expect(segment.duration_in_days).to eq(31)
      end

      it "counts an end-of-day value at nanosecond precision as the exclusive midnight" do
        customer = build(:customer, timezone: "UTC")
        segment = described_class.new(customer:, started_at: Time.utc(2026, 8, 1),
          ended_at: Time.utc(2026, 8, 30, 23, 59, 59, 999_999) + Rational(999, 1_000_000_000))

        expect(segment.duration_in_days).to eq(30)
      end
    end

    describe "#elapsed_period_ratio" do
      it "measures elapsed progress independently from service proration" do
        segment = described_class.new(customer: build(:customer, timezone: "UTC"),
          started_at: Time.zone.parse("2026-08-20"), ended_at: described_class.inclusive_end(Time.zone.parse("2026-08-30")),
          cycle_started_at: Time.zone.parse("2026-08-01"), proration_ratio: 0.5)

        expect(segment.elapsed_period_ratio(at: Time.zone.parse("2026-08-21"))).to eq(2.fdiv(10))
        expect(segment.proration_ratio).to eq(0.5)
      end
    end

    describe "#rate" do
      it "prefers a rate override" do
        override = build(:rate_override)
        segment = described_class.new(rate_card_rate: build(:rate_card_rate), rate_override: override)

        expect(segment.rate).to eq(override)
      end
    end

    describe "#prorated_min_amount_cents" do
      it "keeps fractional cents unrounded" do
        rate = build(:rate_card_rate, min_amount_cents: 1_001)
        segment = described_class.new(rate_card_rate: rate, currency: "USD", proration_ratio: 0.5)

        expect(segment.prorated_min_amount_cents).to eq(BigDecimal("500.5"))
      end
    end
  end
end
