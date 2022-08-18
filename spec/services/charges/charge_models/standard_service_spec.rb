# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::StandardService, type: :service do
  subject(:apply_standard_service) do
    described_class.apply(charge: charge, aggregation_result: aggregation_result)
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:aggregation) { 10 }

  let(:charge) do
    create(
      :standard_charge,
      charge_model: 'standard',
      properties: {
        amount: '500',
      },
    )
  end

  it 'applies the charge model to the value' do
    expect(apply_standard_service.amount).to eq(5000)
  end
end
