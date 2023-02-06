# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebhookJob, type: :job do
  subject(:send_webhook_job) { described_class }

  let(:webhook_invoice_service) { instance_double(Webhooks::InvoicesService) }
  let(:webhook_add_on_service) { instance_double(Webhooks::AddOnService) }
  let(:webhook_event_service) { instance_double(Webhooks::EventService) }
  let(:organization) { create(:organization, webhook_url: 'http://foo.bar') }
  let(:invoice) { create(:invoice, organization:) }

  context 'when webhook_type is invoice' do
    before do
      allow(Webhooks::InvoicesService).to receive(:new)
        .with(invoice)
        .and_return(webhook_invoice_service)
      allow(webhook_invoice_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      send_webhook_job.perform_now(:invoice, invoice)

      expect(Webhooks::InvoicesService).to have_received(:new)
      expect(webhook_invoice_service).to have_received(:call)
    end
  end

  context 'when webhook_type is add_on' do
    before do
      allow(Webhooks::AddOnService).to receive(:new)
        .with(invoice)
        .and_return(webhook_add_on_service)
      allow(webhook_add_on_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      send_webhook_job.perform_now(:add_on, invoice)

      expect(Webhooks::AddOnService).to have_received(:new)
      expect(webhook_add_on_service).to have_received(:call)
    end
  end

  context 'when webhook_type is event' do
    let(:object) do
      {
        input_params: {
          customer_id: 'customer',
          transaction_id: SecureRandom.uuid,
          code: 'code',
        },
        error: 'Code does not exist',
        organization_id: organization.id,
      }
    end

    before do
      allow(Webhooks::EventService).to receive(:new)
        .with(object)
        .and_return(webhook_event_service)
      allow(webhook_event_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(:event, object)

      expect(Webhooks::EventService).to have_received(:new)
      expect(webhook_event_service).to have_received(:call)
    end
  end

  context 'when webhook_type is payment_provider_invoice_payment_errors' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::InvoicePaymentFailureService) }

    let(:webhook_options) do
      {
        provider_error: {
          message: 'message',
          error_code: 'code',
        },
      }
    end

    before do
      allow(Webhooks::PaymentProviders::InvoicePaymentFailureService).to receive(:new)
        .with(invoice, webhook_options)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        :payment_provider_invoice_payment_error,
        invoice,
        webhook_options,
      )

      expect(Webhooks::PaymentProviders::InvoicePaymentFailureService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is payment_provider_customer_created' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::CustomerCreatedService) }
    let(:customer) { create(:customer) }

    before do
      allow(Webhooks::PaymentProviders::CustomerCreatedService).to receive(:new)
        .with(customer)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        :payment_provider_customer_created,
        customer,
      )

      expect(Webhooks::PaymentProviders::CustomerCreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is payment_provider_customer_checkout_url' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::CustomerCheckoutService) }
    let(:customer) { create(:customer) }

    before do
      allow(Webhooks::PaymentProviders::CustomerCheckoutService).to receive(:new)
        .with(customer, checkout_url: 'https://example.com')
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        :payment_provider_customer_checkout_url,
        customer,
        checkout_url: 'https://example.com',
      )

      expect(Webhooks::PaymentProviders::CustomerCheckoutService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is payment_provider_customer_error' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::CustomerErrorService) }
    let(:customer) { create(:customer) }

    let(:webhook_options) do
      {
        provider_error: {
          message: 'message',
          error_code: 'code',
        },
      }
    end

    before do
      allow(Webhooks::PaymentProviders::CustomerErrorService).to receive(:new)
        .with(customer, webhook_options)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        :payment_provider_customer_error,
        customer,
        webhook_options,
      )

      expect(Webhooks::PaymentProviders::CustomerErrorService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is credit_note.created' do
    let(:webhook_service) { instance_double(Webhooks::CreditNotes::CreatedService) }
    let(:credit_note) { create(:credit_note) }

    before do
      allow(Webhooks::CreditNotes::CreatedService).to receive(:new)
        .with(credit_note)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'credit_note.created',
        credit_note,
      )

      expect(Webhooks::CreditNotes::CreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is credit_note.generated' do
    let(:webhook_service) { instance_double(Webhooks::CreditNotes::GeneratedService) }
    let(:credit_note) { create(:credit_note) }

    before do
      allow(Webhooks::CreditNotes::GeneratedService).to receive(:new)
        .with(credit_note)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'credit_note.generated',
        credit_note,
      )

      expect(Webhooks::CreditNotes::GeneratedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is credit_note.provider_refund_failure' do
    let(:webhook_service) { instance_double(Webhooks::CreditNotes::PaymentProviderRefundFailureService) }
    let(:credit_note) { create(:credit_note) }

    let(:webhook_options) do
      {
        provider_error: {
          message: 'message',
          error_code: 'code',
        },
      }
    end

    before do
      allow(Webhooks::CreditNotes::PaymentProviderRefundFailureService).to receive(:new)
        .with(credit_note, webhook_options)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      described_class.perform_now(
        'credit_note.provider_refund_failure',
        credit_note,
        webhook_options,
      )

      expect(Webhooks::CreditNotes::PaymentProviderRefundFailureService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is invoice.drafted' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::DraftedService) }
    let(:invoice) { create(:invoice, organization:) }

    before do
      allow(Webhooks::Invoices::DraftedService).to receive(:new)
        .with(invoice)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'invoice.drafted',
        invoice,
      )

      expect(Webhooks::Invoices::DraftedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is subscription.terminated' do
    let(:webhook_service) { instance_double(Webhooks::Subscriptions::TerminatedService) }
    let(:subscription) { create(:subscription) }

    before do
      allow(Webhooks::Subscriptions::TerminatedService).to receive(:new)
        .with(subscription)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'subscription.terminated',
        subscription,
      )

      expect(Webhooks::Subscriptions::TerminatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook type is invoice.payment_status_updated' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::PaymentStatusUpdatedService) }
    let(:invoice) { create(:invoice, organization:) }

    before do
      allow(Webhooks::Invoices::PaymentStatusUpdatedService).to receive(:new)
        .with(invoice)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'invoice.payment_status_updated',
        invoice,
      )

      expect(Webhooks::Invoices::PaymentStatusUpdatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'with not implemented webhook type' do
    it 'raises a NotImplementedError' do
      expect { send_webhook_job.perform_now(:subscription, invoice) }
        .to raise_error(NotImplementedError)
    end
  end
end
