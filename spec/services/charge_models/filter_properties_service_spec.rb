# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::FilterPropertiesService, type: :service do
  subject(:filter_service) { described_class.new(chargeable:, properties:) }

  let(:properties) { {amount: 100} }

  describe "#call" do
    context "with a charge" do
      let(:chargeable) { build(:charge, charge_model: "standard") }

      it "delegates to ChargeService" do
        expect(ChargeModels::FilterProperties::ChargeService).to receive(:new)
          .with(chargeable:, properties:)
          .and_call_original

        filter_service.call
      end
    end

    context "with a fixed charge" do
      let(:chargeable) { build(:fixed_charge, charge_model: "standard") }

      it "delegates to FixedChargeService" do
        expect(ChargeModels::FilterProperties::FixedChargeService).to receive(:new)
          .with(chargeable:, properties:)
          .and_call_original

        filter_service.call
      end
    end

    context "with an unsupported resource" do
      let(:chargeable) { Object.new }

      it "raises ArgumentError" do
        expect { filter_service.call }.to raise_error(ArgumentError, "Unsupported chargeable type: Object")
      end
    end
  end
end
