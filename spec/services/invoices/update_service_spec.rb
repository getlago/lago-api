# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::UpdateService do
  subject(:invoice_service) do
    described_class.new(invoice:, params: update_args, webhook_notification:)
  end

  let(:invoice) { create(:invoice) }
  let(:invoice_id) { invoice.id }
  let(:webhook_notification) { false }

  let(:update_args) do
    {
      payment_status: 'succeeded',
    }
  end

  let(:result) { invoice_service.call }

  describe 'call' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)
    end

    it 'updates the invoice' do
      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.invoice.payment_status).to eq(update_args[:payment_status])
      end
    end

    it 'calls SegmentTrackJob' do
      result

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.payment_status,
        },
      )
    end

    context 'with attached fees' do
      it 'euqueus a job to update the payment_status of the fees' do
        result

        expect(Invoices::UpdateFeesPaymentStatusJob)
          .to have_been_enqueued
          .with(invoice)
      end
    end

    context 'with metadata' do
      let(:invoice_metadata) { create(:invoice_metadata, invoice:) }
      let(:another_invoice_metadata) { create(:invoice_metadata, invoice:, key: 'test', value: '1') }
      let(:update_args) do
        {
          metadata: [
            {
              id: invoice_metadata.id,
              key: 'new key',
              value: 'new value',
            },
            {
              key: 'Added key',
              value: 'Added value',
            },
          ],
        }
      end

      before do
        invoice_metadata
        another_invoice_metadata
      end

      it 'updates metadata' do
        metadata_keys = result.invoice.metadata.pluck(:key)
        metadata_ids = result.invoice.metadata.pluck(:id)

        expect(result.invoice.metadata.count).to eq(2)
        expect(metadata_keys).to eq(['new key', 'Added key'])
        expect(metadata_ids).to include(invoice_metadata.id)
        expect(metadata_ids).not_to include(another_invoice_metadata.id)
      end

      context 'when invoice is in draft status' do
        let(:invoice) { create(:invoice, status: 'draft') }

        it 'fails to update metadata' do
          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq('metadata_on_draft_invoice')
          end
        end
      end

      context 'when more than five metadata objects are provided' do
        let(:update_args) do
          {
            metadata: [
              {
                id: invoice_metadata.id,
                key: 'new key',
                value: 'new value',
              },
              {
                key: 'Added key1',
                value: 'Added value1',
              },
              {
                key: 'Added key2',
                value: 'Added value2',
              },
              {
                key: 'Added key3',
                value: 'Added value3',
              },
              {
                key: 'Added key4',
                value: 'Added value4',
              },
              {
                key: 'Added key5',
                value: 'Added value5',
              },
            ],
          }
        end

        it 'fails to update invoice with metadata' do
          aggregate_failures do
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:metadata)
            expect(result.error.messages[:metadata]).to include('invalid_count')
          end
        end
      end
    end

    context 'when invoice type is credit and new payment_status is succeeded' do
      let(:subscription) { create(:subscription, customer: invoice.customer) }
      let(:wallet) { create(:wallet, customer: invoice.customer, balance: 10.0, credits_balance: 10.0) }
      let(:wallet_transaction) do
        create(:wallet_transaction, wallet:, amount: 15.0, credit_amount: 15.0, status: 'pending')
      end
      let(:fee) do
        create(
          :fee,
          fee_type: 'credit',
          invoiceable_type: 'WalletTransaction',
          invoiceable_id: wallet_transaction.id,
          invoice:,
        )
      end

      before do
        wallet_transaction
        fee
        subscription
        invoice.update(invoice_type: 'credit')
      end

      it 'calls Invoices::PrepaidCreditJob' do
        result

        expect(Invoices::PrepaidCreditJob).to have_received(:perform_later).with(invoice)
      end
    end

    context 'with payment_status update and notification is turned on' do
      let(:webhook_notification) { true }

      it 'delivers a webhook' do
        result

        expect(SendWebhookJob).to have_been_enqueued.with(
          'invoice.payment_status_updated',
          invoice,
        )
      end

      context 'when payment status has not changed' do
        let(:invoice) { create(:invoice, payment_status: :succeeded) }

        it 'does not deliver a webhook' do
          result

          expect(SendWebhookJob).not_to have_been_enqueued.with(
            'invoice.payment_status_updated',
            invoice,
          )
        end
      end
    end

    context 'when invoice does not exist' do
      let(:invoice) { nil }

      it 'returns an error' do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq('invoice_not_found')
      end
    end

    context 'when invoice payment_status is invalid' do
      let(:update_args) do
        {
          payment_status: 'Foo Bar',
        }
      end

      it 'returns an error' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:payment_status)
          expect(result.error.messages[:payment_status]).to include('value_is_invalid')
        end
      end
    end

    context 'with validation error' do
      before do
        invoice.issuing_date = nil
        invoice.save(validate: false)
      end

      it 'returns an error' do
        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:issuing_date]).to eq(['value_is_mandatory'])
        end
      end
    end
  end
end
