# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModels::BaseService, type: :service do
  subject(:base_service) { described_class.new(fixed_charge:, aggregation_result:, properties:) }

  let(:fixed_charge) { create(:fixed_charge) }
  let(:aggregation_result) { BaseService::Result.new }
  let(:properties) { fixed_charge.properties }

  before do
    aggregation_result.aggregation = 10
    aggregation_result.current_usage_units = 10
    aggregation_result.full_units_number = 10
    aggregation_result.count = 1
  end

  describe "#apply" do
    it "raises NotImplementedError for compute_amount" do
      expect { base_service.apply }.to raise_error(NotImplementedError)
    end

    it "raises NotImplementedError for unit_amount" do
      allow(base_service).to receive(:compute_amount).and_return(100)
      expect { base_service.apply }.to raise_error(NotImplementedError)
    end
  end

  describe "#amount_details" do
    it "returns empty hash by default" do
      expect(base_service.send(:amount_details)).to eq({})
    end
  end
end 