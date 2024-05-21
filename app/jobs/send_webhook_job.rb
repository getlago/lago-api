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
    'invoice.payment_dispute_lost' => Webhooks::Invoices::PaymentDisputeLostService,
    'invoice.payment_status_updated' => Webhooks::Invoices::PaymentStatusUpdatedService,
    'invoice.payment_failure' => Webhooks::PaymentProviders::InvoicePaymentFailureService,
    'event.error' => Webhooks::Events::ErrorService,
    'events.errors' => Webhooks::Events::ValidationErrorsService,
    'fee.created' => Webhooks::Fees::PayInAdvanceCreatedService,
    'customer.accounting_provider_created' => Webhooks::Integrations::CustomerCreatedService,
    'customer.accounting_provider_error' => Webhooks::Integrations::CustomerErrorService,
    'customer.payment_provider_created' => Webhooks::PaymentProviders::CustomerCreatedService,
    'customer.payment_provider_error' => Webhooks::PaymentProviders::CustomerErrorService,
    'customer.checkout_url_generated' => Webhooks::PaymentProviders::CustomerCheckoutService,
    'customer.vies_check' => Webhooks::Customers::ViesCheckService,
    'credit_note.created' => Webhooks::CreditNotes::CreatedService,
    'credit_note.generated' => Webhooks::CreditNotes::GeneratedService,
    'credit_note.provider_refund_failure' => Webhooks::CreditNotes::PaymentProviderRefundFailureService,
    'payment_provider.error' => Webhooks::PaymentProviders::ErrorService,
    'subscription.terminated' => Webhooks::Subscriptions::TerminatedService,
    'subscription.started' => Webhooks::Subscriptions::StartedService,
    'subscription.termination_alert' => Webhooks::Subscriptions::TerminationAlertService,
    'subscription.trial_ended' => Webhooks::Subscriptions::TrialEndedService,
    'wallet.depleted_ongoing_balance' => Webhooks::Wallets::DepletedOngoingBalanceService,
    'wallet_transaction.created' => Webhooks::WalletTransactions::CreatedService,
    'wallet_transaction.updated' => Webhooks::WalletTransactions::UpdatedService
  }.freeze

  def perform(webhook_type, object, options = {}, webhook_id = nil)
    raise(NotImplementedError) unless WEBHOOK_SERVICES.include?(webhook_type)

    # NOTE: This condition is only temporary to handle enqueued jobs
    # TODO: Remove this condition after queued jobs are processed
    if webhook_id
      SendHttpWebhookJob.perform_later(Webhook.find(webhook_id))
      return
    end

    WEBHOOK_SERVICES.fetch(webhook_type).new(object:, options:).call
  end
end
