# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModelFactory, type: :service do
  subject(:factory) { described_class }

  let(:fixed_charge) { build(:fixed_charge) }
  let(:aggregation_result) { BaseService::Result.new }
  let(:properties) { fixed_charge.properties }

  let(:result) { factory.new_instance(fixed_charge:, aggregation_result:, properties:) }

  describe "#new_instance" do
    context "with standard charge model" do
      it { expect(result).to be_a(FixedCharges::ChargeModels::StandardService) }
    end

    context "with graduated charge model" do
      let(:fixed_charge) { build(:fixed_charge, charge_model: "graduated") }

      it { expect(result).to be_a(FixedCharges::ChargeModels::GraduatedService) }
    end

    context "with volume charge model" do
      let(:fixed_charge) { build(:fixed_charge, charge_model: "volume") }

      it { expect(result).to be_a(FixedCharges::ChargeModels::VolumeService) }
    end
  end

  describe "#charge_model_class" do
    context "with standard charge model" do
      it "returns StandardService" do
        expect(factory.charge_model_class(fixed_charge:)).to eq(FixedCharges::ChargeModels::StandardService)
      end
    end

    context "with graduated charge model" do
      let(:fixed_charge) { build(:fixed_charge, charge_model: "graduated") }

      it "returns GraduatedService" do
        expect(factory.charge_model_class(fixed_charge:)).to eq(FixedCharges::ChargeModels::GraduatedService)
      end
    end
  end
end
