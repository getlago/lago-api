# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycle do
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
      expect(subject).to validate_numericality_of(:proration_ratio)
        .is_greater_than_or_equal_to(0)
        .is_less_than_or_equal_to(1)
    end
  end

  describe "#rate_properties" do
    subject(:rate_properties) { billing_cycle.rate_properties }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, rate_properties: {"amount" => "10.00"}) }
    let(:billing_cycle) { described_class.new(rate_card_rate:, rate_properties: {"amount" => "10.00"}) }

    it "returns the stored rate properties" do
      expect(rate_properties).to eq({"amount" => "10.00"})
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, rate_properties: {"amount" => "5.00"}) }
      let(:billing_cycle) { described_class.new(rate_card_rate:, rate_override:, rate_properties: {"amount" => "5.00"}) }

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

  describe "#pricing_unit_conversion_rate" do
    subject(:pricing_unit_conversion_rate) { billing_cycle.pricing_unit_conversion_rate }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, applied_pricing_unit_conversion_rate: 0.5) }
    let(:billing_cycle) { described_class.new(rate_card_rate:) }

    it "returns the rate conversion rate" do
      expect(pricing_unit_conversion_rate).to eq(0.5)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, pricing_unit_conversion_rate: 0.25) }
      let(:billing_cycle) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override conversion rate" do
        expect(pricing_unit_conversion_rate).to eq(0.25)
      end
    end
  end

  describe "#min_amount_cents" do
    subject(:min_amount_cents) { billing_cycle.min_amount_cents }

    let(:rate_card_rate) { build_stubbed(:rate_card_rate, min_amount_cents: 1_000) }
    let(:billing_cycle) { described_class.new(rate_card_rate:) }

    it "returns the rate minimum amount" do
      expect(min_amount_cents).to eq(1_000)
    end

    context "with a rate override" do
      let(:rate_override) { build_stubbed(:rate_override, min_amount_cents: 2_000) }
      let(:billing_cycle) { described_class.new(rate_card_rate:, rate_override:) }

      it "returns the override minimum amount" do
        expect(min_amount_cents).to eq(2_000)
      end
    end
  end
end
