# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GraduatedService, type: :service do
  subject(:graduated_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :charge,
      charge_model: :graduated,
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

  context 'when value is 0' do
    it 'applies the flat_rate' do
      expect(graduated_service.apply(value: 0).amount_cents).to eq(2)
    end
  end
end
