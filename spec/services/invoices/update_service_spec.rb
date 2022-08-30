# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::UpdateService do
  subject(:invoice_service) { described_class.new }

  let(:invoice) { create(:invoice) }
  let(:invoice_id) { invoice.id }

  describe 'update_from_api' do
    let(:update_args) do
      {
        status: 'succeeded',
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)
    end

    it 'updates the invoice' do
      result = invoice_service.update_from_api(
        invoice_id: invoice_id,
        params: update_args,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.invoice.status).to eq(update_args[:status])
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.update_from_api(
        invoice_id: invoice_id,
        params: update_args,
      ).invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.status
        }
      )
    end

    context 'when invoice type is credit and new status is succeeded' do
      let(:subscription) { create(:subscription, customer: invoice.customer) }
      let(:wallet) { create(:wallet, customer: invoice.customer, balance: 10.0, credits_balance: 10.0) }
      let(:wallet_transaction) do
        create(:wallet_transaction, wallet: wallet, amount: 15.0, credit_amount: 15.0, status: 'pending')
      end
      let(:fee) do
        create(:fee,
          fee_type: 'credit',
          invoiceable_type: 'WalletTransaction',
          invoiceable_id: wallet_transaction.id,
          invoice: invoice
        )
      end

      before do
        wallet_transaction
        fee
        subscription
        invoice.update(invoice_type: 'credit')
      end

      it 'calls Invoices::PrepaidCreditJob' do
        invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(Invoices::PrepaidCreditJob).to have_received(:perform_later).with(invoice)
      end
    end

    context 'when invoice does not exist' do
      let(:invoice_id) { 'invalid' }

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    context 'when invoice status is invalid' do
      let(:update_args) do
        {
          status: 'Foo Bar',
        }
      end

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('invalid_status')
      end
    end

    context 'when invoice status is not present' do
      let(:update_args) {{}}

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('invalid_status')
      end
    end

    context 'with validation error' do
      before do
        invoice.issuing_date = nil
        invoice.save(validate: false)
      end

      it 'returns an error' do
        result = invoice_service.update_from_api(
          invoice_id: invoice_id,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end
  end
end
