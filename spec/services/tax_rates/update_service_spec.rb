# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxRates::UpdateService, type: :service do
  subject(:update_service) { described_class.new(tax_rate:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax_rate) { create(:tax_rate, organization:) }

  describe '#call' do
    before { tax_rate }

    let(:params) do
      {
        name: 'updated name',
        code: 'updated code',
        value: 15.0,
        description: 'updated desc',
      }
    end

    it 'updates the tax rate' do
      result = update_service.call
      expect(result).to be_success

      aggregate_failures do
        expect(result.tax_rate.name).to eq(params[:name])
        expect(result.tax_rate.code).to eq(params[:code])
        expect(result.tax_rate.value).to eq(params[:value])
        expect(result.tax_rate.description).to eq(params[:description])
      end
    end

    it 'returns tax rate in the result' do
      result = update_service.call
      expect(result.tax_rate).to be_a(TaxRate)
    end

    context 'when tax rate is not found' do
      let(:tax_rate) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_rate_not_found')
        end
      end
    end

    context 'with validation error' do
      let(:params) do
        {
          id: tax_rate.id,
          name: nil,
          code: 'code',
          amount_cents: 100,
          amount_currency: 'EUR',
        }
      end

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end
  end
end
