# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreateService, type: :service do
  subject(:create_service) do
    described_class.new(customer:, timestamp: timestamp.to_i, fees:, currency:)
  end

  let(:timestamp) { Time.zone.now.beginning_of_month }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:currency) { 'EUR' }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: 'desc-123'
      },
      {
        add_on_code: add_on_second.code
      }
    ]
  end

  describe 'call' do
    before do
      tax

      allow(SegmentTrackJob).to receive(:perform_later)
      CurrentContext.source = 'api'
    end

    it 'creates an invoice' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.invoice.issuing_date.to_date).to eq(timestamp)
        expect(result.invoice.invoice_type).to eq('one_off')
        expect(result.invoice.payment_status).to eq('pending')
        expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(2)
        expect(result.invoice.fees.pluck(:description)).to contain_exactly('desc-123', add_on_second.description)

        expect(result.invoice.currency).to eq('EUR')
        expect(result.invoice.fees_amount_cents).to eq(2800)

        expect(result.invoice.taxes_amount_cents).to eq(560)
        expect(result.invoice.taxes_rate).to eq(20)
        expect(result.invoice.applied_taxes.count).to eq(1)

        expect(result.invoice.total_amount_cents).to eq(3360)

        expect(result.invoice).to be_finalized
      end
    end

    it_behaves_like 'syncs invoice' do
      let(:service_call) { create_service.call }
    end

    it_behaves_like 'syncs sales order' do
      let(:service_call) { create_service.call }
    end

    it 'calls SegmentTrackJob' do
      invoice = create_service.call.invoice

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'invoice_created',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          invoice_type: invoice.invoice_type
        }
      )
    end

    it 'creates a payment' do
      payment_create_service = instance_double(Invoices::Payments::CreateService)
      allow(Invoices::Payments::CreateService)
        .to receive(:new).and_return(payment_create_service)
      allow(payment_create_service)
        .to receive(:call)

      create_service.call

      expect(Invoices::Payments::CreateService).to have_received(:new)
      expect(payment_create_service).to have_received(:call)
    end

    it 'enqueues a SendWebhookJob' do
      expect do
        create_service.call
      end.to have_enqueued_job(SendWebhookJob)
    end

    it 'does not enqueue an SendEmailJob' do
      expect do
        create_service.call
      end.not_to have_enqueued_job(SendEmailJob)
    end

    context 'when invoice amount in cents is zero' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 0,
            units: 2,
            description: 'desc-123'
          }
        ]
      end

      it 'creates an succeeded invoice' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.invoice_type).to eq('one_off')
          expect(result.invoice.payment_status).to eq('succeeded')
          expect(result.invoice.fees.where(fee_type: :add_on).count).to eq(1)
          expect(result.invoice.fees.pluck(:description)).to contain_exactly('desc-123')

          expect(result.invoice.currency).to eq('EUR')
          expect(result.invoice.fees_amount_cents).to eq(0)
          expect(result.invoice.taxes_amount_cents).to eq(0)
          expect(result.invoice.taxes_rate).to eq(20)
          expect(result.invoice.total_amount_cents).to eq(0)

          expect(result.invoice).to be_finalized
        end
      end
    end

    context 'with lago_premium' do
      around { |test| lago_premium!(&test) }

      it 'enqueues an SendEmailJob' do
        expect do
          create_service.call
        end.to have_enqueued_job(SendEmailJob)
      end

      context 'when organization does not have right email settings' do
        before { customer.organization.update!(email_settings: []) }

        it 'does not enqueue an SendEmailJob' do
          expect do
            create_service.call
          end.not_to have_enqueued_job(SendEmailJob)
        end
      end
    end

    context 'when organization does not have a webhook endpoint' do
      before { customer.organization.webhook_endpoints.destroy_all }

      it 'does not enqueues a SendWebhookJob' do
        expect do
          create_service.call
        end.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context 'with customer timezone' do
      before { customer.update!(timezone: 'America/Los_Angeles') }

      let(:timestamp) { DateTime.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = create_service.call

        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end

    context 'when currency does not match' do
      let(:currency) { 'NOK' }

      it 'fails' do
        result = create_service.call

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
        result = create_service.call

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
        result = create_service.call

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
        result = create_service.call

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
            description: 'desc-123'
          },
          {
            add_on_code: 'invalid'
          }
        ]
      end

      it 'returns a not found error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('add_on_not_found')
        end
      end
    end
  end
end
