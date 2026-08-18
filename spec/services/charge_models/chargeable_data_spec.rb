# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::ChargeableData do
  describe ".from_charge" do
    let(:billable_metric) { create(:sum_billable_metric, recurring: true) }
    let(:charge) { create(:standard_charge, billable_metric:, prorated: true) }

    it "builds normalized data from a charge" do
      data = described_class.from_charge(charge)

      expect(data.charge_model).to eq(charge.charge_model)
      expect(data.properties).to eq(charge.properties)
      expect(data.prorated).to eq(true)
      expect(data.accepts_target_wallet).to eq(false)
      expect(data.currency).to eq(charge.plan.amount.currency)
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
    let(:fixed_charge) { create(:fixed_charge, charge_model: :standard, prorated: true, properties: {amount: "10"}) }

    it "builds normalized data from a fixed charge" do
      data = described_class.from_fixed_charge(fixed_charge)

      expect(data.charge_model).to eq(fixed_charge.charge_model)
      expect(data.properties).to eq(fixed_charge.properties)
      expect(data.prorated).to eq(true)
      expect(data.accepts_target_wallet).to eq(false)
      expect(data.currency).to eq(fixed_charge.plan.amount.currency)
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
    let(:charge) { create(:standard_charge) }
    let(:data) { described_class.from_charge(charge) }

    it "returns copied chargeable data" do
      copied_data = data.with(properties: {amount: "20"})

      expect(copied_data.charge_model).to eq(charge.charge_model)
      expect(copied_data.properties).to eq({amount: "20"})
      expect(copied_data.prorated).to eq(charge.prorated?)
      expect(copied_data.accepts_target_wallet).to eq(charge.accepts_target_wallet)
      expect(copied_data.currency).to eq(charge.plan.amount.currency)
    end

    it "requires a currency" do
      expect do
        data.with(currency: nil)
      end.to raise_error(ArgumentError, "currency is mandatory")
    end
  end
end
