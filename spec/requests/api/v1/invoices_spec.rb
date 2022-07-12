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

  describe 'show' do
    let(:invoice) { create(:invoice) }

    it 'returns a invoice' do
      get_with_token(
        organization,
        "/api/v1/invoices/#{invoice.id}"
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:invoice]

      expect(result[:lago_id]).to eq(invoice.id)
      expect(result[:status]).to eq(invoice.status)
    end

    context 'when invoice does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/invoices/555"
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:invoice) { create(:invoice, subscription: subscription) }
    let(:subscription) { create(:subscription, customer: customer) }
    let(:customer) {  create(:customer, organization: organization) }

    before { invoice }

    it 'returns invoices' do
      get_with_token(organization, '/api/v1/invoices')

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:invoices]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(invoice.id)
      expect(records.first[:status]).to eq(invoice.status)
    end

    context 'with pagination' do
      let(:invoice2) { create(:invoice, subscription: subscription2) }
      let(:subscription2) { create(:subscription, customer: customer) }

      before { invoice2 }

      it 'returns invoices with correct meta data' do
        get_with_token(organization, '/api/v1/invoices?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:invoices].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end

    context 'with issuing_date params' do
      let(:invoice) { create(:invoice, subscription: subscription, issuing_date: 5.days.ago.to_date) }
      let(:invoice2) { create(:invoice, subscription: subscription2, issuing_date: 3.days.ago.to_date) }
      let(:subscription2) { create(:subscription, customer: customer) }
      let(:invoice3) { create(:invoice, subscription: subscription3, issuing_date: 1.day.ago.to_date) }
      let(:subscription3) { create(:subscription, customer: customer) }

      before do
        invoice2
        invoice3
      end

      it 'returns invoices with correct issuing date' do
        get_with_token(
          organization,
          "/api/v1/invoices?issuing_date_from=#{2.days.ago.to_date}&issuing_date_to=#{Date.tomorrow.to_date}"
        )

        expect(response).to have_http_status(:success)

        records = JSON.parse(response.body, symbolize_names: true)[:invoices]

        expect(records.count).to eq(1)
        expect(records.first[:lago_id]).to eq(invoice3.id)
      end
    end
  end
end
