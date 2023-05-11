# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedTaxRates::CreateService, type: :service do
  subject(:create_service) { described_class.new(customer:, tax_rate:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { create(:tax_rate, organization:) }

  describe '#call' do
    it 'creates an applied tax rate' do
      expect { create_service.call }.to change(AppliedTaxRate, :count).by(1)
    end

    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('customer_not_found')
        end
      end
    end

    context 'when tax rate is not found' do
      let(:tax_rate) { nil }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_rate_not_found')
        end
      end
    end
  end
end
