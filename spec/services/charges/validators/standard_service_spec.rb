# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::StandardService, type: :service do
  subject(:standard_service) { described_class.new(charge: charge) }

  let(:charge) { build(:standard_charge, properties: properties) }
  let(:properties) { {} }

  describe '.valid?' do
    it 'is invalid' do
      aggregate_failures do
        expect(standard_service).not_to be_valid
        expect(standard_service.result.error).to be_a(BaseService::ValidationFailure)
        expect(standard_service.result.error.messages.keys).to include(:amount)
        expect(standard_service.result.error.messages[:amount]).to include('invalid_amount')
      end
    end

    context 'when amount is not an integer' do
      let(:properties) { { amount: 'Foo' } }

      it 'is invalid' do
        aggregate_failures do
          expect(standard_service).not_to be_valid
          expect(standard_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(standard_service.result.error.messages.keys).to include(:amount)
          expect(standard_service.result.error.messages[:amount]).to include('invalid_amount')
        end
      end
    end

    context 'when amount is negative' do
      let(:properties) { { amount: '-12' } }

      it 'is invalid' do
        aggregate_failures do
          expect(standard_service).not_to be_valid
          expect(standard_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(standard_service.result.error.messages.keys).to include(:amount)
          expect(standard_service.result.error.messages[:amount]).to include('invalid_amount')
        end
      end
    end

    context 'with an applicable amount' do
      let(:properties) { { amount: '12' } }

      it { expect(standard_service).to be_valid }
    end
  end
end
