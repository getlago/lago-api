# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:invoice) { create(:invoice, customer: customer) }

  describe 'UPDATE /invoices' do
    let(:update_params) do
      { status: 'succeeded' }
    end

    it 'updates an invoice' do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}", { invoice: update_params })

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to eq(invoice.id)
      expect(json[:invoice][:status]).to eq('succeeded')
    end

    context 'when invoice does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/invoices/555', { invoice: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /invoices/:id' do
    it 'returns a invoice' do
      group = create(:group)
      create(:fee, invoice_id: invoice.id, group: group)

      get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
        expect(json[:invoice][:status]).to eq(invoice.status)
        expect(json[:invoice][:customer]).not_to be_nil
        expect(json[:invoice][:subscriptions]).not_to be_nil
        expect(json[:invoice][:fees].first).to include(lago_group_id: group.id)
        expect(json[:invoice][:credits]).not_to be_nil
      end
    end

    context 'when invoice does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/invoices/555')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoices belongs to an other organization' do
      let(:invoice) { create(:invoice) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:invoice) { create(:invoice, customer: customer) }
    let(:customer) { create(:customer, organization: organization) }

    before { invoice }

    it 'returns invoices' do
      get_with_token(organization, '/api/v1/invoices')

      expect(response).to have_http_status(:success)
      expect(json[:invoices].count).to eq(1)
      expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
      expect(json[:invoices].first[:status]).to eq(invoice.status)
    end

    context 'with pagination' do
      let(:invoice2) { create(:invoice, customer: customer) }

      before { invoice2 }

      it 'returns invoices with correct meta data' do
        get_with_token(organization, '/api/v1/invoices?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        expect(json[:invoices].count).to eq(1)
        expect(json[:meta][:current_page]).to eq(1)
        expect(json[:meta][:next_page]).to eq(2)
        expect(json[:meta][:prev_page]).to eq(nil)
        expect(json[:meta][:total_pages]).to eq(2)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end

    context 'with issuing_date params' do
      let(:invoice) { create(:invoice, customer: customer, issuing_date: 5.days.ago.to_date) }
      let(:invoice2) { create(:invoice, customer: customer, issuing_date: 3.days.ago.to_date) }
      let(:invoice3) { create(:invoice, customer: customer, issuing_date: 1.day.ago.to_date) }

      before do
        invoice2
        invoice3
      end

      it 'returns invoices with correct issuing date' do
        get_with_token(
          organization,
          "/api/v1/invoices?issuing_date_from=#{2.days.ago.to_date}&issuing_date_to=#{Date.tomorrow.to_date}",
        )

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(invoice3.id)
      end
    end

    context 'with external_customer_id params' do
      it 'returns invoices of the customer' do
        second_customer = create(:customer, organization: organization)
        invoice = create(:invoice, customer: second_customer)

        get_with_token(organization, "/api/v1/invoices?external_customer_id=#{second_customer.external_id}")

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
      end
    end
  end
end
