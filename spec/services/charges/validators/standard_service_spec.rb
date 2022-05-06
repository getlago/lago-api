# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::StandardService, type: :service do
  subject(:standard_service) { described_class.new(charge: charge) }

  let(:charge) { build(:standard_charge, properties: properties) }
  let(:properties) { {} }

  describe '.validate' do
    it 'ensure the presence of an amount' do
      result = standard_service.validate

      expect(result.error).to include(:invalid_amount)
    end

    context 'when amount is not an integer' do
      let(:properties) { { amount_cents: 'Foo' } }

      it { expect(standard_service.validate.error).to include(:invalid_amount) }
    end

    context 'when amount is negative' do
      let(:properties) { { amount_cents: -12 } }

      it { expect(standard_service.validate.error).to include(:invalid_amount) }
    end

    context 'with an applicable amount' do
      let(:properties) { { amount_cents: 12 } }

      it { expect(standard_service.validate).to be_success }
    end
  end
end
