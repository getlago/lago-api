# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedTaxRates::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(applied_tax_rate:) }

  let(:applied_tax_rate) { create(:applied_tax_rate) }

  describe '#call' do
    before { applied_tax_rate }

    it 'destroys the applied tax rate' do
      expect { destroy_service.call }.to change(AppliedTaxRate, :count).by(-1)
    end

    context 'when applied tax rate is not found' do
      let(:applied_tax_rate) { nil }

      it 'returns an error' do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('applied_tax_rate_not_found')
        end
      end
    end
  end
end
