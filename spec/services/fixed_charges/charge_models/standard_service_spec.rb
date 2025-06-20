# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModels::StandardService, type: :service do
  subject(:apply_standard_service) do
    described_class.apply(
      fixed_charge:,
      aggregation_result:,
      properties: fixed_charge.properties
    )
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:amount) { "10" }
  let(:aggregation) { 5 }

  let(:fixed_charge) do
    create(
      :fixed_charge,
      properties: {amount:}
    )
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  it "applies the model to the values" do
    expect(apply_standard_service.amount).to eq(50)
    expect(apply_standard_service.unit_amount).to eq(10)
  end

  context "when aggregation is zero" do
    let(:aggregation) { 0 }

    it "applies the model to the values" do
      expect(apply_standard_service.amount).to eq(0)
      expect(apply_standard_service.unit_amount).to eq(0)
    end
  end

  context "when amount is zero" do
    let(:amount) { "0" }

    it "applies the model to the values" do
      expect(apply_standard_service.amount).to eq(0)
      expect(apply_standard_service.unit_amount).to eq(0)
    end
  end
end 