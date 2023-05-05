# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  describe 'create' do
    let(:add_on_first) { create(:add_on, organization:) }
    let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
    let(:customer_external_id) { customer.external_id }
    let(:create_params) do
      {
        external_customer_id: customer_external_id,
        currency: 'EUR',
        fees: [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
          },
          {
            add_on_code: add_on_second.code,
          },
        ],
      }
    end

    it 'creates a invoice' do
      post_with_token(organization, '/api/v1/invoices', { invoice: create_params })

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to be_present
      expect(json[:invoice][:issuing_date]).to eq(Time.current.to_date.to_s)
      expect(json[:invoice][:invoice_type]).to eq('one_off')
      expect(json[:invoice][:amount_cents]).to eq(2800)
      expect(json[:invoice][:vat_amount_cents]).to eq(560)
      expect(json[:invoice][:total_amount_cents]).to eq(3360)
      expect(json[:invoice][:currency]).to eq('EUR')
    end

    context 'when customer does not exist' do
      let(:customer_external_id) { 'invalid' }

      it 'returns a not found error' do
        post_with_token(organization, '/api/v1/invoices', { invoice: create_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when add_on does not exist' do
      let(:create_params) do
        {
          external_customer_id: customer_external_id,
          currency: 'EUR',
          fees: [
            {
              add_on_code: add_on_first.code,
              unit_amount_cents: 1200,
              units: 2,
              description: 'desc-123',
            },
            {
              add_on_code: 'invalid',
            },
          ],
        }
      end

      it 'returns a not found error' do
        post_with_token(organization, '/api/v1/invoices', { invoice: create_params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'UPDATE /invoices' do
    let(:update_params) do
      { payment_status: 'succeeded' }
    end

    it 'updates an invoice' do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}", { invoice: update_params })

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to eq(invoice.id)
      expect(json[:invoice][:payment_status]).to eq('succeeded')
    end

    context 'when invoice does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/invoices/555', { invoice: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with metadata' do
      let(:update_params) do
        {
          metadata: [
            {
              key: 'Hello',
              value: 'Hi',
            },
          ],
        }
      end

      it 'returns a success' do
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}", { invoice: update_params })

        metadata = json[:invoice][:metadata]
        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:invoice][:lago_id]).to eq(invoice.id)

          expect(metadata).to be_present
          expect(metadata.first[:key]).to eq('Hello')
          expect(metadata.first[:value]).to eq('Hi')
        end
      end
    end
  end

  describe 'GET /invoices/:id' do
    it 'returns a invoice' do
      group = create(:group)
      create(:fee, invoice_id: invoice.id, group:)

      get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
        expect(json[:invoice][:payment_status]).to eq(invoice.payment_status)
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

    context 'when invoice has a fee for a deleted billable metric' do
      let(:billable_metric) { create(:billable_metric, :deleted) }
      let(:group) { create(:group, :deleted, billable_metric:) }
      let(:fee) { create(:charge_fee, invoice:, group:, charge:) }

      let(:group_property) do
        build(
          :group_property,
          :deleted,
          group:,
          values: { amount: '10', amount_currency: 'EUR' },
        )
      end

      let(:charge) do
        create(:standard_charge, :deleted, billable_metric:, group_properties: [group_property])
      end

      before do
        charge
        fee
      end

      it 'returns the invoice with the deleted resources' do
        get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
          expect(json[:invoice][:payment_status]).to eq(invoice.payment_status)
          expect(json[:invoice][:status]).to eq(invoice.status)
          expect(json[:invoice][:customer]).not_to be_nil
          expect(json[:invoice][:subscriptions]).not_to be_nil
          expect(json[:invoice][:credits]).not_to be_nil

          json_fee = json[:invoice][:fees].first
          expect(json_fee[:lago_group_id]).to eq(group.id)
          expect(json_fee[:item][:type]).to eq('charge')
          expect(json_fee[:item][:code]).to eq(billable_metric.code)
          expect(json_fee[:item][:name]).to eq(billable_metric.name)
        end
      end
    end
  end

  describe 'GET /invoices' do
    let(:invoice) { create(:invoice, :draft, customer:, organization:) }
    let(:customer) { create(:customer, organization:) }

    before { invoice }

    it 'returns invoices' do
      get_with_token(organization, '/api/v1/invoices')

      expect(response).to have_http_status(:success)
      expect(json[:invoices].count).to eq(1)
      expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
      expect(json[:invoices].first[:payment_status]).to eq(invoice.payment_status)
      expect(json[:invoices].first[:status]).to eq(invoice.status)
    end

    context 'with pagination' do
      let(:invoice2) { create(:invoice, customer:, organization:) }

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
      let(:invoice) { create(:invoice, customer:, issuing_date: 5.days.ago.to_date, organization:) }
      let(:invoice2) { create(:invoice, customer:, issuing_date: 3.days.ago.to_date, organization:) }
      let(:invoice3) { create(:invoice, customer:, issuing_date: 1.day.ago.to_date, organization:) }

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
        second_customer = create(:customer, organization:)
        invoice = create(:invoice, customer: second_customer, organization:)

        get_with_token(organization, "/api/v1/invoices?external_customer_id=#{second_customer.external_id}")

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
      end

      context 'with deleted customer' do
        let(:customer) { create(:customer, :deleted, organization:) }

        it 'returns the invoices of the customer' do
          get_with_token(organization, "/api/v1/invoices?external_customer_id=#{customer.external_id}")

          aggregate_failures do
            expect(response).to have_http_status(:success)
            expect(json[:invoices].count).to eq(1)
            expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
            expect(json[:invoices].first[:customer][:lago_id]).to eq(customer.id)
          end
        end
      end
    end

    context 'with status params' do
      it 'returns invoices for the given status' do
        invoice = create(:invoice, customer:, organization:)

        get_with_token(organization, '/api/v1/invoices?status=finalized')

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(invoice.id)
      end
    end

    context 'with payment status param' do
      let(:invoice) { create(:invoice, customer:, payment_status: :succeeded, organization:) }
      let(:invoice2) { create(:invoice, customer:, payment_status: :failed, organization:) }
      let(:invoice3) { create(:invoice, customer:, payment_status: :pending, organization:) }

      before do
        invoice2
        invoice3
      end

      it 'returns invoices with correct payment status' do
        get_with_token(organization, '/api/v1/invoices?payment_status=pending')

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(invoice3.id)
      end
    end
  end

  describe 'PUT /invoices/:id/refresh' do
    context 'when invoice does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/invoices/555/refresh', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoice is draft' do
      let(:invoice) { create(:invoice, :draft, customer:, organization:) }

      it 'updates the invoice' do
        expect {
          put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
        }.to change { invoice.reload.updated_at }
      end

      it 'returns the invoice' do
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})

        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
      end
    end

    context 'when invoice is finalized' do
      let(:invoice) { create(:invoice, customer:, organization:) }

      it 'does not update the invoice' do
        expect {
          put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
        }.not_to change { invoice.reload.updated_at }
      end

      it 'returns the invoice' do
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})

        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
      end
    end
  end

  describe 'PUT /invoices/:id/finalize' do
    let(:invoice) { create(:invoice, :draft, customer:, organization:) }

    context 'when invoice does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/invoices/555/finalize', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoice is not draft' do
      let(:invoice) { create(:invoice, customer:, status: :finalized, organization:) }

      it 'returns a not found error' do
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'finalizes the invoice' do
      expect {
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
      }.to change { invoice.reload.status }.from('draft').to('finalized')
    end

    it 'returns the invoice' do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to eq(invoice.id)
    end
  end

  describe 'POST /invoices/:id/download' do
    let(:invoice) { create(:invoice, :draft, customer:, organization:) }

    context 'when invoice is draft' do
      it 'returns not found' do
        post_with_token(organization, "/api/v1/invoices/#{invoice.id}/download")
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /invoices/:id/retry_payment' do
    let(:retry_service) { instance_double(Invoices::Payments::RetryService) }

    before do
      allow(Invoices::Payments::RetryService).to receive(:new).and_return(retry_service)
      allow(retry_service).to receive(:call).and_return(BaseService::Result.new)
    end

    it 'calls retry service' do
      post_with_token(organization, "/api/v1/invoices/#{invoice.id}/retry_payment")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(retry_service).to have_received(:call)
      end
    end

    context 'when invoice does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/invoices/555/retry_payment')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoices belongs to an other organization' do
      let(:invoice) { create(:invoice, organization:) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/invoices/#{invoice.id}/retry_payment")

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
