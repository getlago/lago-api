# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebhookJob, type: :job do
  subject(:send_webhook_job) { described_class }

  let(:organization) { create(:organization, webhook_url: 'http://foo.bar') }
  let(:invoice) { create(:invoice, organization:) }

  context 'when webhook_type is invoice.created' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::CreatedService) }

    before do
      allow(Webhooks::Invoices::CreatedService).to receive(:new)
        .with(object: invoice, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      send_webhook_job.perform_now('invoice.created', invoice)

      expect(Webhooks::Invoices::CreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is invoice.add_on_added' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::AddOnCreatedService) }

    before do
      allow(Webhooks::Invoices::AddOnCreatedService).to receive(:new)
        .with(object: invoice, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook invoice service' do
      send_webhook_job.perform_now('invoice.add_on_added', invoice)

      expect(Webhooks::Invoices::AddOnCreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is invoice.paid_credit_added' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::PaidCreditAddedService) }

    before do
      allow(Webhooks::Invoices::PaidCreditAddedService).to receive(:new)
        .with(object: invoice, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook invoice paid credit added service' do
      send_webhook_job.perform_now('invoice.paid_credit_added', invoice)

      expect(Webhooks::Invoices::PaidCreditAddedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is event' do
    let(:webhook_service) { instance_double(Webhooks::Events::ErrorService) }
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
      allow(Webhooks::Events::ErrorService).to receive(:new)
        .with(object:, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now('event.error', object)

      expect(Webhooks::Events::ErrorService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is events.errors' do
    let(:webhook_service) { instance_double(Webhooks::Events::ValidationErrorsService) }
    let(:object) { organization }
    let(:options) do
      {
        errors: [
          invalid_code: [SecureRandom.uuid],
          missing_aggregation_property: [SecureRandom.uuid],
          missing_group_key: [SecureRandom.uuid],
        ],
      }
    end

    before do
      allow(Webhooks::Events::ValidationErrorsService).to receive(:new)
        .with(object:, options:, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now('events.errors', object, options)

      expect(Webhooks::Events::ValidationErrorsService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is fee.created' do
    let(:webhook_service) { instance_double(Webhooks::Fees::PayInAdvanceCreatedService) }
    let(:fee) { create(:fee) }

    before do
      allow(Webhooks::Fees::PayInAdvanceCreatedService).to receive(:new)
        .with(object: fee, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook fee service' do
      send_webhook_job.perform_now('fee.created', fee)

      expect(Webhooks::Fees::PayInAdvanceCreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is event.error' do
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
        .with(object: invoice, options: webhook_options, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        'invoice.payment_failure',
        invoice,
        webhook_options,
      )

      expect(Webhooks::PaymentProviders::InvoicePaymentFailureService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is customer.payment_provider_created' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::CustomerCreatedService) }
    let(:customer) { create(:customer) }

    before do
      allow(Webhooks::PaymentProviders::CustomerCreatedService).to receive(:new)
        .with(object: customer, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        'customer.payment_provider_created',
        customer,
      )

      expect(Webhooks::PaymentProviders::CustomerCreatedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is customer.checkout_url_generated' do
    let(:webhook_service) { instance_double(Webhooks::PaymentProviders::CustomerCheckoutService) }
    let(:customer) { create(:customer) }

    before do
      allow(Webhooks::PaymentProviders::CustomerCheckoutService).to receive(:new)
        .with(object: customer, options: {checkout_url: 'https://example.com'}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'customer.checkout_url_generated',
        customer,
        checkout_url: 'https://example.com',
      )

      expect(Webhooks::PaymentProviders::CustomerCheckoutService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook_type is customer.payment_provider_error' do
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
        .with(object: customer, options: webhook_options, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook event service' do
      send_webhook_job.perform_now(
        'customer.payment_provider_error',
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
        .with(object: credit_note, options: {}, webhook_id: nil)
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
        .with(object: credit_note, options: {}, webhook_id: nil)
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
        .with(object: credit_note, options: webhook_options, webhook_id: nil)
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
        .with(object: invoice, options: {}, webhook_id: nil)
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
        .with(object: subscription, options: {}, webhook_id: nil)
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

  context 'when webhook_type is subscription.termination_alert' do
    let(:webhook_service) { instance_double(Webhooks::Subscriptions::TerminationAlertService) }
    let(:subscription) { create(:subscription) }

    before do
      allow(Webhooks::Subscriptions::TerminationAlertService).to receive(:new)
        .with(object: subscription, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'subscription.termination_alert',
        subscription,
      )

      expect(Webhooks::Subscriptions::TerminationAlertService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook type is invoice.payment_status_updated' do
    let(:webhook_service) { instance_double(Webhooks::Invoices::PaymentStatusUpdatedService) }
    let(:invoice) { create(:invoice, organization:) }

    before do
      allow(Webhooks::Invoices::PaymentStatusUpdatedService).to receive(:new)
        .with(object: invoice, options: {}, webhook_id: nil)
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

  context 'when webhook type is subscription.started' do
    let(:webhook_service) { instance_double(Webhooks::Subscriptions::StartedService) }
    let(:subscription) { create(:subscription) }

    before do
      allow(Webhooks::Subscriptions::StartedService).to receive(:new)
        .with(object: subscription, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'subscription.started',
        subscription,
      )

      expect(Webhooks::Subscriptions::StartedService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end

  context 'when webhook type is customer.vies_check' do
    let(:webhook_service) { instance_double(Webhooks::Customers::ViesCheckService) }
    let(:customer) { create(:customer) }

    before do
      allow(Webhooks::Customers::ViesCheckService).to receive(:new)
        .with(object: customer, options: {}, webhook_id: nil)
        .and_return(webhook_service)
      allow(webhook_service).to receive(:call)
    end

    it 'calls the webhook service' do
      send_webhook_job.perform_now(
        'customer.vies_check',
        customer,
      )

      expect(Webhooks::Customers::ViesCheckService).to have_received(:new)
      expect(webhook_service).to have_received(:call)
    end
  end
end
