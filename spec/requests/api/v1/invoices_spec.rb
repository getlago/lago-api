# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice) }

  describe 'UPDATE /invoices' do
    let(:update_params) do
      {
        status: 'succeeded'
      }
    end

    it 'updates an invoice' do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}", { invoice: update_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:invoice]

      expect(result[:lago_id]).to eq(invoice.id)
      expect(result[:status]).to eq('succeeded')
    end

    context 'when invoice does not exist' do
      it 'returns an unprocessable entity error' do
        put_with_token(organization, '/api/v1/invoices/555', { invoice: update_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
