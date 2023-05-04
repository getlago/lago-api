# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::OneOffService, type: :service do
  subject(:invoice_service) do
    described_class.new(customer:, timestamp: timestamp.to_i, fees:, currency:)
  end

  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:currency) { 'EUR' }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: 'desc-123',
      },
      {
        add_on_code: add_on_second.code,
      },
    ]
  end

  describe 'create' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      CurrentContext.source = 'api'
    end

    it 'creates an invoice' do
      result = invoice_service.create

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq('one_off')
        expect(result.invoice.payment_status).to eq('pending')
        expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(2)
        expect(result.invoice.fees.pluck(:description)).to contain_exactly('desc-123', add_on_second.description)

        expect(result.invoice.currency).to eq('EUR')
        expect(result.invoice.fees_amount_cents).to eq(2800)
        expect(result.invoice.vat_amount_cents).to eq(560)
        expect(result.invoice.vat_rate).to eq(20)
        expect(result.invoice.total_amount_cents).to eq(3360)

        expect(result.invoice).to be_finalized
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

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = invoice_service.create

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end

    context 'when currency does not match' do
      let(:currency) { 'NOK' }

      it 'fails' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:currency)
          expect(result.error.messages[:currency]).to include('currencies_does_not_match')
        end
      end
    end

    context 'when currency does not present' do
      let(:currency) { nil }

      before { customer.update!(currency: nil) }

      it 'fails' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:currency)
          expect(result.error.messages[:currency]).to include('value_is_mandatory')
        end
      end
    end

    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns a not found error' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when fees are blank' do
      let(:fees) { [] }

      it 'returns a not found error' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('fees_not_found')
        end
      end
    end

    context 'when add_on_code is invalid' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
          },
          {
            add_on_code: 'invalid',
          },
        ]
      end

      it 'returns a not found error' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('add_on_not_found')
        end
      end
    end
  end
end
