# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::BuildDefaultPropertiesService, type: :service do
  subject(:service) { described_class.new(charge_model) }

  describe "call" do
    context "when standard charge model" do
      let(:charge_model) { :standard }

      it "returns standard default properties" do
        expect(service.call).to eq({amount: "0"})
      end
    end

    context "when graduated charge model" do
      let(:charge_model) { :graduated }

      it "returns graduated default properties" do
        expect(service.call).to eq(
          {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "0",
                flat_amount: "0"
              }
            ]
          }
        )
      end
    end

    context "when volume charge model" do
      let(:charge_model) { :volume }

      it "returns volume default properties" do
        expect(service.call).to eq(
          {
            volume_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: "0",
                flat_amount: "0"
              }
            ]
          }
        )
      end
    end
  end
end
