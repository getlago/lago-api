# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::AddOnService, type: :service do
  subject(:invoice_service) do
    described_class.new(applied_add_on:, datetime:)
  end

  let(:datetime) { Time.zone.now }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:applied_add_on) { create(:applied_add_on, customer:) }

  let(:tax) { create(:tax, rate: 20, organization:) }

  before { tax }

  describe 'create' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.subscriptions.first).to be_nil
        expect(result.invoice).to have_attributes(
          issuing_date: datetime.to_date,
          invoice_type: 'add_on',
          payment_status: 'pending',
          currency: 'EUR',
          fees_amount_cents: 200,
          sub_total_excluding_taxes_amount_cents: 200,
          taxes_amount_cents: 40,
          taxes_rate: 20,
          sub_total_including_taxes_amount_cents: 240,
          total_amount_cents: 240,
        )

        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice).to be_finalized
      end
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        invoice_service.create
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'does not enqueue an SendEmailJob' do
      expect do
        invoice_service.create
      end.not_to have_enqueued_job(SendEmailJob)
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an SendEmailJob' do
        expect do
          invoice_service.create
        end.to have_enqueued_job(SendEmailJob)
      end

      context 'when organization does not have right email settings' do
        before { applied_add_on.customer.organization.update!(email_settings: []) }

        it 'does not enqueue an SendEmailJob' do
          expect do
            invoice_service.create
          end.not_to have_enqueued_job(SendEmailJob)
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
          invoice_type: invoice.invoice_type
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

    it_behaves_like 'syncs invoice' do
      let(:service_call) { invoice_service.create }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { invoice_service.create }
    end

    context 'when organization does not have a webhook endpoint' do
      before { applied_add_on.customer.organization.webhook_endpoints.destroy_all }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          invoice_service.create
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { applied_add_on.customer.update!(timezone: 'America/Los_Angeles') }

      let(:datetime) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end
  end
end
