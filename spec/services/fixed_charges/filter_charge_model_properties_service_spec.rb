# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::FilterChargeModelPropertiesService, type: :service do
  subject(:filter_service) { described_class.new(fixed_charge:, properties:) }

  let(:charge_model) { nil }
  let(:fixed_charge) { build(:fixed_charge, charge_model:) }

  let(:properties) do
    {
      amount: 100,
      graduated_ranges: [{from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "1"}],
      volume_ranges: [{from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "1"}]
    }
  end

  describe "#call" do
    context "with standard charge_model" do
      let(:charge_model) { "standard" }

      it { expect(filter_service.call.properties.keys).to include("amount") }
    end

    context "with graduated charge_model" do
      let(:charge_model) { "graduated" }

      it { expect(filter_service.call.properties.keys).to include("graduated_ranges") }
    end

    context "with volume charge_model" do
      let(:charge_model) { "volume" }

      it { expect(filter_service.call.properties.keys).to include("volume_ranges") }
    end
  end
end
