# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::PricingStructure do
  describe ".from_charge" do
    let(:billable_metric) { build(:sum_billable_metric, recurring: true) }
    let(:charge) { build(:standard_charge, billable_metric:, prorated: true) }

    it "builds normalized data from a charge" do
      structure = described_class.from_charge(charge)

      expect(structure.charge_model).to eq(charge.charge_model)
      expect(structure.properties).to eq(charge.properties)
      expect(structure.prorated).to eq(true)
      expect(structure.accepts_target_wallet).to eq(false)
      expect(structure.currency).to eq(Money::Currency.new(charge.plan.amount_currency))
    end

    context "when chargeable is not a charge" do
      let(:charge) { build(:fixed_charge) }

      it "raises an error" do
        expect { described_class.from_charge(charge) }
          .to raise_error(NotImplementedError, "Chargeable: FixedCharge is not implemented")
      end
    end
  end

  describe ".from_fixed_charge" do
    let(:fixed_charge) { build(:fixed_charge, charge_model: :standard, prorated: true, properties: {amount: "10"}) }

    it "builds normalized data from a fixed charge" do
      structure = described_class.from_fixed_charge(fixed_charge)

      expect(structure.charge_model).to eq(fixed_charge.charge_model)
      expect(structure.properties).to eq(fixed_charge.properties)
      expect(structure.prorated).to eq(true)
      expect(structure.accepts_target_wallet).to eq(false)
      expect(structure.currency).to eq(Money::Currency.new(fixed_charge.plan.amount_currency))
    end

    context "when chargeable is not a fixed charge" do
      let(:fixed_charge) { build(:standard_charge) }

      it "raises an error" do
        expect { described_class.from_fixed_charge(fixed_charge) }
          .to raise_error(NotImplementedError, "Chargeable: Charge is not implemented")
      end
    end
  end

  describe ".from_billing_cycle" do
    let(:organization) { build(:organization) }
    let(:customer) { build(:customer, organization:) }
    let(:subscription) { build(:subscription, organization:, customer:) }
    let(:billable_metric) { build(:sum_billable_metric, organization:, recurring: true) }
    let(:product) { build(:product, organization:, billable_metric:) }
    let(:rate_card) { build(:rate_card, organization:, product:, currency: "USD", proration: true) }
    let(:rate_card_rate) do
      build(
        :rate_card_rate,
        organization:,
        rate_card:,
        rate_model: "volume",
        rate_properties: {
          "volume_ranges" => [
            {"from_value" => 0, "to_value" => nil, "per_unit_amount" => "10", "flat_amount" => "0"}
          ]
        }
      )
    end
    let(:subscription_rate_card) do
      build(:subscription_rate_card, organization:, customer:, subscription:, rate_card:)
    end
    let(:billing_cycle) do
      build(
        :billing_cycle,
        organization:,
        customer:,
        subscription:,
        subscription_rate_card:,
        rate_card_rate:,
        rate_properties: rate_card_rate.rate_properties
      )
    end

    it "builds normalized data from a billing cycle" do
      structure = described_class.from_billing_cycle(billing_cycle)

      expect(structure.charge_model).to eq(rate_card_rate.rate_model)
      expect(structure.properties).to eq(billing_cycle.rate_properties)
      expect(structure.prorated).to eq(true)
      expect(structure.accepts_target_wallet).to eq(false)
      expect(structure.currency).to eq(Money::Currency.new("USD"))
    end

    context "when chargeable is not a billing cycle" do
      let(:billing_cycle) { build(:standard_charge) }

      it "raises an error" do
        expect { described_class.from_billing_cycle(billing_cycle) }
          .to raise_error(NotImplementedError, "Chargeable: Charge is not implemented")
      end
    end
  end

  describe "#with" do
    let(:charge) { build(:standard_charge) }
    let(:structure) { described_class.from_charge(charge) }

    it "returns copied pricing structure" do
      copied_structure = structure.with(properties: {amount: "20"})

      expect(copied_structure.charge_model).to eq(charge.charge_model)
      expect(copied_structure.properties).to eq({amount: "20"})
      expect(copied_structure.prorated).to eq(charge.prorated?)
      expect(copied_structure.accepts_target_wallet).to eq(charge.accepts_target_wallet)
      expect(copied_structure.currency).to eq(Money::Currency.new(charge.plan.amount_currency))
    end

    it "requires a currency" do
      expect do
        structure.with(currency: nil)
      end.to raise_error(ArgumentError, "currency is mandatory")
    end
  end
end
