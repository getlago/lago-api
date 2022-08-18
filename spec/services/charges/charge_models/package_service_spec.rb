# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PackageService, type: :service do
  subject(:apply_package_service) do
    described_class.apply(charge: charge, aggregation_result: aggregation_result)
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:aggregation) { 121 }

  let(:charge) do
    create(
      :package_charge,
      properties: {
        amount: '100',
        package_size: 10,
        free_units: 0,
      },
    )
  end

  it 'applies the package size to the value' do
    expect(apply_package_service.amount).to eq(1300)
  end

  context 'with free_units' do
    before { charge.properties['free_units'] = 10 }

    it 'substracts the free units from the value' do
      expect(apply_package_service.amount).to eq(1200)
    end

    context 'when free units is higher than the value' do
      before { charge.properties['free_units'] = 200 }

      it { expect(apply_package_service.amount).to eq(0) }
    end
  end
end
