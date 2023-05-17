# frozen_string_literal: true

module PaymentProviders
  class AdyenService < BaseService
    WEBHOOKS_EVENTS = [
      'AUTHORISATION', 'REFUND', 'REFUND_FAILED'
    ].freeze

    def create_or_update(**args)
      adyen_provider = PaymentProviders::AdyenProvider.find_or_initialize_by(
        organization_id: args[:organization].id
      )

      adyen_provider.api_key = args[:api_key] if args.key?(:api_key)
      adyen_provider.merchant_account = args[:merchant_account] if args.key?(:merchant_account)
      adyen_provider.live_prefix = args[:live_prefix] if args.key?(:live_prefix)
      adyen_provider.hmac_key = args[:hmac_key] if args.key?(:hmac_key)
      adyen_provider.save!

      result.adyen_provider = adyen_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def handle_incoming_webhook(organization_id:, body:)
      organization = Organization.find_by(id: organization_id)
      validator = ::Adyen::Utils::HmacValidator.new
      hmac_key = organization.adyen_payment_provider.hmac_key

      if hmac_key && !validator.valid_notification_hmac?(body, hmac_key)
        return result.service_failure!(code: 'webhook_error', message: 'Invalid signature')
      end

      PaymentProviders::Adyen::HandleEventJob.perform_later(organization:, event_json: body.to_json)

      result.event = body
      result
    rescue JSON::ParserError
      result.service_failure!(code: 'webhook_error', message: 'Invalid payload')
    end

    def handle_event(organization:, event_json:)
      event = JSON.parse(event_json)
      unless WEBHOOKS_EVENTS.include?(event["eventCode"])
        return result.service_failure!(
          code: 'webhook_error',
          message: "Invalid adyen event code: #{event["eventCode"]}",
        )
      end

      case event["eventCode"]
      when 'AUTHORISATION'
        return result if event["success"] != "true"

        service = PaymentProviderCustomers::AdyenService.new

        if event.dig("amount", "value") == 0
          result = service.preauthorise(organization, event)
        end

        result.raise_if_error! || result
      when 'REFUND'
        service = CreditNotes::Refunds::AdyenService.new

        provider_refund_id = event["pspReference"]
        status = event["success"] == "true" ? :succeeded : :failed

        result = service.update_status(provider_refund_id:, status:)
        result.raise_if_error! || result
      when 'REFUND_FAILED'
        return result if event["success"] != "true"

        service = CreditNotes::Refunds::AdyenService.new

        provider_refund_id = event["pspReference"]
        
        result = service.update_status(provider_refund_id:, status: :failed)
        result.raise_if_error! || result
      end
    end
  end
end
