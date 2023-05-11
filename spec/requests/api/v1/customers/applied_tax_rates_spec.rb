# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Customers::AppliedTaxRatesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { create(:tax_rate, organization:) }

  describe 'POST /applied_tax_rates' do
    it 'creates an applied tax rate' do
      expect do
        post_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_tax_rates",
          { applied_tax_rate: { tax_rate_code: tax_rate.code } },
        )
      end.to change(AppliedTaxRate, :count).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_tax_rate][:lago_id]).to be_present
        expect(json[:applied_tax_rate][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_tax_rate][:lago_tax_rate_id]).to eq(tax_rate.id)
      end
    end

    context 'when customer does not exist' do
      it 'returns not_found error' do
        post_with_token(organization, '/api/v1/customers/unknown/applied_tax_rates', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax rate does not exist' do
      it 'returns not_found error' do
        post_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_tax_rates",
          { applied_tax_rate: { tax_rate_code: 'unknown' } },
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /applied_tax_rates/:tax_rate_code' do
    let(:applied_tax_rate) { create(:applied_tax_rate, customer:, tax_rate:) }

    before { applied_tax_rate }

    it 'deletes an applied tax rate' do
      expect do
        delete_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_tax_rates/#{tax_rate.code}",
        )
      end.to change(AppliedTaxRate, :count).by(-1)
    end

    it 'returns the deleted applied tax rate' do
      delete_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/applied_tax_rates/#{tax_rate.code}",
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_tax_rate][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_tax_rate][:external_customer_id]).to eq(customer.external_id)
        expect(json[:applied_tax_rate][:lago_tax_rate_id]).to eq(tax_rate.id)
        expect(json[:applied_tax_rate][:tax_rate_code]).to eq(tax_rate.code)
      end
    end

    context 'when customer does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/unknown/applied_tax_rates/#{tax_rate.code}")
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax rate does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_tax_rates/unknown")
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when applied tax rate does not exist' do
      let(:applied_tax_rate) { nil }

      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_tax_rates/#{tax_rate.code}")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
