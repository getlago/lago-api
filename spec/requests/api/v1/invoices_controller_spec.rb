# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }

  before { tax }

  describe 'POST /invoices' do
    let(:add_on_first) { create(:add_on, code: 'first', organization:) }
    let(:add_on_second) { create(:add_on, code: 'second', amount_cents: 400, organization:) }
    let(:customer_external_id) { customer.external_id }
    let(:invoice_display_name) { 'Invoice item #1' }
    let(:create_params) do
      {
        external_customer_id: customer_external_id,
        currency: 'EUR',
        fees: [
          {
            add_on_code: add_on_first.code,
            invoice_display_name:,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
            tax_codes: [tax.code]
          },
          {
            add_on_code: add_on_second.code
          }
        ]
      }
    end

    it 'creates an invoice' do
      post_with_token(organization, '/api/v1/invoices', {invoice: create_params})

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(
        lago_id: String,
        issuing_date: Time.current.to_date.to_s,
        invoice_type: 'one_off',
        amount_cents: 2800,
        taxes_amount_cents: 560,
        total_amount_cents: 3360,
        currency: 'EUR'
      )

      fee = json[:invoice][:fees].find { |f| f[:item][:code] == 'first' }

      expect(fee[:item][:invoice_display_name]).to eq(invoice_display_name)
      expect(json[:invoice][:applied_taxes][0][:tax_code]).to eq(tax.code)
    end

    context 'when customer does not exist' do
      let(:customer_external_id) { 'invalid' }

      it 'returns a not found error' do
        post_with_token(organization, '/api/v1/invoices', {invoice: create_params})

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
              description: 'desc-123'
            },
            {
              add_on_code: 'invalid'
            }
          ]
        }
      end

      it 'returns a not found error' do
        post_with_token(organization, '/api/v1/invoices', {invoice: create_params})

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /invoices/:id' do
    let(:update_params) do
      {payment_status: 'succeeded'}
    end

    it 'updates an invoice' do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}", {invoice: update_params})

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to eq(invoice.id)
      expect(json[:invoice][:payment_status]).to eq('succeeded')
    end

    context 'when invoice does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/invoices/555', {invoice: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with metadata' do
      let(:update_params) do
        {
          metadata: [
            {
              key: 'Hello',
              value: 'Hi'
            }
          ]
        }
      end

      it 'returns a success' do
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}", {invoice: update_params})

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
    it 'returns an invoice' do
      charge_filter = create(:charge_filter)
      create(:fee, invoice_id: invoice.id, charge_filter:)

      get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          lago_id: invoice.id,
          payment_status: invoice.payment_status,
          status: invoice.status,
          customer: Hash,
          subscriptions: [],
          credits: [],
          applied_taxes: []
        )
        expect(json[:invoice][:fees].first).to include(lago_charge_filter_id: charge_filter.id)
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
      let(:billable_metric_filter) { create(:billable_metric_filter, :deleted, billable_metric:) }
      let(:charge_filter) do
        create(:charge_filter, :deleted, charge:, properties: {amount: '10'})
      end
      let(:charge_filter_value) do
        create(
          :charge_filter_value,
          :deleted,
          charge_filter:,
          billable_metric_filter:,
          values: [billable_metric_filter.values.first]
        )
      end
      let(:fee) { create(:charge_fee, invoice:, charge_filter:, charge:) }

      let(:charge) do
        create(:standard_charge, :deleted, billable_metric:)
      end

      before do
        charge
        fee
        charge_filter_value
      end

      it 'returns the invoice with the deleted resources' do
        get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:invoice]).to include(
            lago_id: invoice.id,
            payment_status: invoice.payment_status,
            status: invoice.status,
            customer: Hash,
            subscriptions: [],
            credits: [],
            applied_taxes: []
          )

          json_fee = json[:invoice][:fees].first
          expect(json_fee[:lago_charge_filter_id]).to eq(charge_filter.id)
          expect(json_fee[:item]).to include(
            type: 'charge',
            code: billable_metric.code,
            name: billable_metric.name
          )
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
      expect(json[:invoices].first).to include(
        lago_id: invoice.id,
        payment_status: invoice.payment_status,
        status: invoice.status
      )
    end

    context 'with pagination' do
      let(:invoice2) { create(:invoice, customer:, organization:) }

      before { invoice2 }

      it 'returns invoices with correct meta data' do
        get_with_token(organization, '/api/v1/invoices?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        expect(json[:invoices].count).to eq(1)
        expect(json[:meta]).to include(
          current_page: 1,
          next_page: 2,
          prev_page: nil,
          total_pages: 2,
          total_count: 2
        )
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
          "/api/v1/invoices?issuing_date_from=#{2.days.ago.to_date}&issuing_date_to=#{Date.tomorrow.to_date}"
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

    context 'with payment overdue param' do
      let(:invoice) { create(:invoice, customer:, payment_overdue: true, organization:) }

      it 'returns payment overdue invoices' do
        create(:invoice, customer:, organization:)
        get_with_token(organization, '/api/v1/invoices?payment_overdue=true')

        expect(response).to have_http_status(:success)
        expect(json[:invoices].map { |i| i[:lago_id] }).to eq([invoice.id])
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

  describe 'POST /invoices/:id/void' do
    let(:invoice) { create(:invoice, status:, payment_status:, customer:, organization:) }
    let(:payment_status) { :pending }

    context 'when invoice does not exist' do
      let(:status) { :finalized }

      it 'returns a not found error' do
        post_with_token(organization, '/api/v1/invoices/555/void', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoice is draft' do
      let(:status) { :draft }

      it 'returns a method not allowed error' do
        post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", {})
        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context 'when invoice is voided' do
      let(:status) { :voided }

      it 'returns a method not allowed error' do
        post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", {})
        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context 'when invoice is finalized' do
      let(:status) { :finalized }

      context 'when the payment status is succeeded' do
        let(:payment_status) { :succeeded }

        it 'returns a method not allowed error' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", {})
          expect(response).to have_http_status(:method_not_allowed)
        end
      end

      context 'when the payment status is not succeeded' do
        let(:payment_status) { [:pending, :failed].sample }

        it 'voids the invoice' do
          expect {
            post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", {})
          }.to change { invoice.reload.status }.from('finalized').to('voided')
        end

        it 'returns the invoice' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", {})

          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
        end
      end
    end
  end

  describe 'POST /invoices/:id/lose_dispute' do
    context 'when invoice does not exist' do
      it 'returns not found error' do
        post_with_token(organization, '/api/v1/invoices/555/lose_dispute', {})
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when invoice exists' do
      let(:invoice) { create(:invoice, customer:, organization:, status:) }

      context 'when invoice is finalized' do
        let(:status) { :finalized }

        it 'marks the dispute as lost' do
          expect {
            post_with_token(organization, "/api/v1/invoices/#{invoice.id}/lose_dispute", {})
          }.to change { invoice.reload.payment_dispute_lost_at }.from(nil)
        end

        it 'returns the invoice' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/lose_dispute", {})

          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
        end
      end

      context 'when invoice is voided' do
        let(:status) { :voided }

        it 'returns method not allowed error' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/lose_dispute", {})
          expect(response).to have_http_status(:method_not_allowed)
        end
      end

      context 'when invoice is draft' do
        let(:status) { :draft }

        it 'returns method not allowed error' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/lose_dispute", {})
          expect(response).to have_http_status(:method_not_allowed)
        end
      end

      context 'when invoice is generating' do
        let(:status) { :generating }

        it 'returns not found error' do
          post_with_token(organization, "/api/v1/invoices/#{invoice.id}/lose_dispute", {})
          expect(response).to have_http_status(:not_found)
        end
      end
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

  describe 'POST /invoices/:id/payment_url' do
    let(:organization) { create(:organization) }
    let(:stripe_provider) { create(:stripe_provider, organization:, code:) }
    let(:customer) { create(:customer, organization:, payment_provider_code: code) }
    let(:code) { 'stripe_1' }

    before do
      create(
        :stripe_customer,
        customer_id: customer.id,
        payment_provider: stripe_provider
      )

      customer.update(payment_provider: 'stripe')

      allow(Stripe::Checkout::Session).to receive(:create)
        .and_return({'url' => 'https://example.com'})
    end

    it 'returns the generated payment url' do
      post_with_token(organization, "/api/v1/invoices/#{invoice.id}/payment_url")

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:invoice_payment_details][:payment_url]).to eq('https://example.com')
      end
    end
  end
end
