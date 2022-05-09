# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GraduatedService, type: :service do
  subject(:graduated_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :graduated_charge,
      properties: [
        {
          from_value: 0,
          to_value: 10,
          per_unit_amount_cents: 10,
          flat_amount_cents: 2,
        },
        {
          from_value: 11,
          to_value: nil,
          per_unit_amount_cents: 5,
          flat_amount_cents: 3,
        },
      ],
    )
  end

  it 'does not apply the flat amount for 0' do
    expect(graduated_service.apply(value: 0).amount_cents).to eq(0)
  end

  it 'applies a unit amount for 1 and the flat rate for 1' do
    expect(graduated_service.apply(value: 1).amount_cents).to eq(12)
  end

  it 'applies all unit amount for top bound' do
    expect(graduated_service.apply(value: 10).amount_cents).to eq(102)
  end

  it 'applies next range flat amount for the next step' do
    expect(graduated_service.apply(value: 11).amount_cents).to eq(110)
  end

  it 'applies next unit amount for more unit in next step' do
    expect(graduated_service.apply(value: 12).amount_cents).to eq(115)
  end
end
