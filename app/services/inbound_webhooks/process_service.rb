# frozen_string_literal: true

module InboundWebhooks
  class ProcessService < BaseService
    WEBHOOK_HANDLER_SERVICES = {
      stripe: PaymentProviders::Stripe::HandleIncomingWebhookService
    }

    def initialize(inbound_webhook:)
      @inbound_webhook = inbound_webhook

      super
    end

    def call
      inbound_webhook.processing!

      handler_result = handler_service_klass.call(inbound_webhook:)

      unless handler_result.success?
        inbound_webhook.failed!
        return handler_result
      end

      inbound_webhook.processed!

      result.inbound_webhook = inbound_webhook
      result
    rescue
      inbound_webhook.failed!
      raise
    end

    private

    attr_reader :inbound_webhook

    def handler_service_klass
      WEBHOOK_HANDLER_SERVICES.fetch(webhook_source) do
        raise NameError, "Invalid inbound webhook source: #{webhook_source}"
      end
    end

    def webhook_source
      inbound_webhook.source.to_sym
    end
  end
end
