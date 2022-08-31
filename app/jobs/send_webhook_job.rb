# frozen_string_literal: true

require Rails.root.join('lib/lago_http_client/lago_http_client')

class SendWebhookJob < ApplicationJob
  queue_as 'webhook'

  retry_on(
    LagoHttpClient::HttpError,
    wait: :exponentially_longer,
    attempts: ENV.fetch('LAGO_WEBHOOK_ATTEMPTS', 3).to_i,
  )

  def perform(webhook_type, object, options = {})
    case webhook_type
    when :invoice
      Webhooks::InvoicesService.new(object).call
    when :add_on
      Webhooks::AddOnService.new(object).call
    when :event
      Webhooks::EventService.new(object).call

    # NOTE: Payment provider related webhooks
    when :payment_provider_invoice_payment_error
      Webhooks::PaymentProviders::InvoicePaymentFailureService.new(object, options).call
    when :payment_provider_customer_created
      Webhooks::PaymentProviders::CustomerCreatedService.new(object).call
    when :payment_provider_customer_error
      Webhooks::PaymentProviders::CustomerErrorService.new(object, options).call

    # NOTE: This add the new way of managing webhooks
    # A refact has to be done to improve webhooks management internally
    when 'invoice.generated'
      Webhooks::Invoices::GeneratedService.new(object).call
    else
      raise NotImplementedError
    end
  end
end
