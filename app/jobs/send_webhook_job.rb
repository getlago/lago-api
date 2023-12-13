# frozen_string_literal: true

require Rails.root.join('lib/lago_http_client/lago_http_client')

class SendWebhookJob < ApplicationJob
  queue_as 'webhook'

  retry_on ActiveJob::DeserializationError, wait: :exponentially_longer, attempts: 6

  WEBHOOK_SERVICES = {
    'invoice.created' => Webhooks::Invoices::CreatedService,
    'invoice.one_off_created' => Webhooks::Invoices::OneOffCreatedService,
    'invoice.add_on_added' => Webhooks::Invoices::AddOnCreatedService,
    'invoice.paid_credit_added' => Webhooks::Invoices::PaidCreditAddedService,
    'invoice.generated' => Webhooks::Invoices::GeneratedService,
    'invoice.drafted' => Webhooks::Invoices::DraftedService,
    'invoice.voided' => Webhooks::Invoices::VoidedService,
    'invoice.payment_status_updated' => Webhooks::Invoices::PaymentStatusUpdatedService,
    'invoice.payment_failure' => Webhooks::PaymentProviders::InvoicePaymentFailureService,
    'event.error' => Webhooks::Events::ErrorService,
    'events.errors' => Webhooks::Events::ValidationErrorsService,
    'fee.created' => Webhooks::Fees::PayInAdvanceCreatedService,
    'customer.payment_provider_created' => Webhooks::PaymentProviders::CustomerCreatedService,
    'customer.payment_provider_error' => Webhooks::PaymentProviders::CustomerErrorService,
    'customer.checkout_url_generated' => Webhooks::PaymentProviders::CustomerCheckoutService,
    'customer.vies_check' => Webhooks::Customers::ViesCheckService,
    'credit_note.created' => Webhooks::CreditNotes::CreatedService,
    'credit_note.generated' => Webhooks::CreditNotes::GeneratedService,
    'credit_note.provider_refund_failure' => Webhooks::CreditNotes::PaymentProviderRefundFailureService,
    'subscription.terminated' => Webhooks::Subscriptions::TerminatedService,
    'subscription.started' => Webhooks::Subscriptions::StartedService,
    'subscription.termination_alert' => Webhooks::Subscriptions::TerminationAlertService,
  }.freeze

  def perform(webhook_type, object, options = {}, webhook_id = nil)
    raise(NotImplementedError) unless WEBHOOK_SERVICES.include?(webhook_type)

    WEBHOOK_SERVICES.fetch(webhook_type).new(object:, options:, webhook_id:).call
  end
end
