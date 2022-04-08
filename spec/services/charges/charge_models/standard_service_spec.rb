# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::StandardService, type: :service do
  subject(:standard_service) { described_class.new(charge: charge) }

  let(:charge) do
    create(
      :charge,
      amount_cents: 500,
      charge_model: 'standard',
    )
  end

  it 'apply the charge model to the value' do
    expect(standard_service.apply(value: 10)).to eq(5000)
  end
end
