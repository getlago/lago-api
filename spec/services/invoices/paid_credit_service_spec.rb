# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PaidCreditService, type: :service do
  subject(:invoice_service) do
    described_class.new(wallet_transaction:, timestamp:)
  end

  let(:timestamp) { Time.current.to_i }

  describe 'create' do
    let(:customer) { create(:customer) }
    let(:subscription) { create(:subscription, customer:) }
    let(:wallet) { create(:wallet, customer:) }
    let(:wallet_transaction) do
      create(:wallet_transaction, wallet:, amount: '15.00', credit_amount: '15.00')
    end

    before do
      wallet_transaction
      subscription
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice).to have_attributes(
          issuing_date: Time.zone.at(timestamp).to_date,
          invoice_type: 'credit',
          payment_status: 'pending',
          currency: 'EUR',
          fees_amount_cents: 1500,
          sub_total_vat_excluded_amount_cents: 1500,
          vat_amount_cents: 0,
          vat_rate: 0,
          sub_total_vat_included_amount_cents: 1500,
          total_amount_cents: 1500,
        )

        expect(result.invoice).to be_finalized
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'does not enqueue an ActionMailer::MailDeliveryJob' do
      expect do
        invoice_service.create
      end.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an ActionMailer::MailDeliveryJob' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end

      context 'when organization does not have right email settings' do
        before { customer.organization.update!(email_settings: []) }

        it 'does not enqueue an ActionMailer::MailDeliveryJob' do
          expect do
            invoice_service.create
          end.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
        end
      end
    end

    it 'calls SegmentTrackJob' do
      invoice = invoice_service.create.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type,
        },
      )
    end

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      invoice_service.create

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    context 'when organization does not have a webhook url' do
      before { customer.organization.update!(webhook_url: nil) }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00').to_i }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end
  end
end
