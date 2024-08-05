# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::DeliverErrorWebhookService, type: :service do
  subject(:webhook_service) { described_class.new(invoice, params) }

  let(:invoice) { create(:invoice) }
  let(:params) do
    {
      'provider_customer_id' => 'customer',
      'provider_error' => {
        'error_message' => 'message',
        'error_code' => 'code'
      }
    }.with_indifferent_access
  end

  describe '.call_async' do
    it 'enqueues a job to send an invoice payment failure webhook' do
      expect do
        webhook_service.call_async
      end.to have_enqueued_job(SendWebhookJob).with('invoice.payment_failure', invoice, params)
    end

    context 'when the invoice is credit? and open?' do
      let(:invoice) do
        invoice = create(:invoice, :credit, status: :open)
        create(:fee, fee_type: :credit, invoice: invoice, invoiceable: wallet_transaction)
        invoice
      end
      let(:wallet_transaction) { create(:wallet_transaction) }

      it 'enqueues a job to send a wallet transaction payment failure webhook' do
        expect do
          webhook_service.call_async
        end.to have_enqueued_job(SendWebhookJob).with('wallet_transaction.payment_failure', wallet_transaction, params)
      end
    end
  end
end
