# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::PackageService, type: :service do
  subject(:package_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :package_charge,
      properties: {
        amount_cents: 100,
        package_size: 10,
      },
    )
  end

  it 'applies the package size to the value' do
    expect(package_service.apply(value: 121).amount_cents).to eq(1300)
  end

  context 'with free_units' do
    before { charge.properties['free_units'] = 10 }

    it 'substracts the free units from the value' do
      expect(package_service.apply(value: 121).amount_cents).to eq(1200)
    end
  end
end
