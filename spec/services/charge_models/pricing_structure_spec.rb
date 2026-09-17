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
