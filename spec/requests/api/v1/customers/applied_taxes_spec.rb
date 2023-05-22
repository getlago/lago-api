# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Customers::AppliedTaxesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:) }

  describe 'POST /applied_taxes' do
    it 'creates an applied tax' do
      expect do
        post_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_taxes",
          { applied_tax: { tax_code: tax.code } },
        )
      end.to change(AppliedTax, :count).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_tax][:lago_id]).to be_present
        expect(json[:applied_tax][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_tax][:lago_tax_id]).to eq(tax.id)
      end
    end

    context 'when customer does not exist' do
      it 'returns not_found error' do
        post_with_token(organization, '/api/v1/customers/unknown/applied_taxes', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax does not exist' do
      it 'returns not_found error' do
        post_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_taxes",
          { applied_tax: { tax_code: 'unknown' } },
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /applied_taxes/:tax_code' do
    let(:applied_tax) { create(:applied_tax, customer:, tax:) }

    before { applied_tax }

    it 'deletes an applied tax' do
      expect do
        delete_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/applied_taxes/#{tax.code}",
        )
      end.to change(AppliedTax, :count).by(-1)
    end

    it 'returns the deleted applied tax' do
      delete_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/applied_taxes/#{tax.code}",
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:applied_tax][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_tax][:external_customer_id]).to eq(customer.external_id)
        expect(json[:applied_tax][:lago_tax_id]).to eq(tax.id)
        expect(json[:applied_tax][:tax_code]).to eq(tax.code)
      end
    end

    context 'when customer does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/unknown/applied_taxes/#{tax.code}")
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_taxes/unknown")
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when applied tax does not exist' do
      let(:applied_tax) { nil }

      it 'returns not_found error' do
        delete_with_token(organization, "/api/v1/customers/#{customer.external_id}/applied_taxes/#{tax.code}")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
