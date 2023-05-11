# frozen_string_literal: true

module PaymentProviders
  class AdyenService < BaseService
    PAYMENT_ACTIONS = %w[paid_out failed cancelled customer_approval_denied charged_back].freeze
    REFUND_ACTIONS = %w[created funds_returned paid refund_settled failed].freeze

    # TODO: Add more events
    WEBHOOKS_EVENTS = [
      'AUTHORISATION'
    ].freeze

    def create_or_update(**args)
      adyen_provider = PaymentProviders::AdyenProvider.find_or_initialize_by(
        organization_id: args[:organization].id,
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

      PaymentProviders::Adyen::HandleEventJob.perform_later(organization:, event_json: body.to_json)
      
      if hmac_key && !validator.valid_notification_hmac?(body, hmac_key)
        return result.service_failure!(code: 'webhook_error', message: 'Invalid signature')
      end

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

        service = PaymentProviderCustomers::AdyenService.new

        # TODO Update payment method
        # result = PaymentProviderCustomers::AdyenService
        #   .new
        #   .update_payment_method(
        #     organization_id: organization.id,
        #     stripe_customer_id: event.data.object.customer,
        #     payment_method_id: event.data.object.payment_method,
        #     metadata: event.data.object.metadata.to_h.symbolize_keys,
        #   )

        return result if event["success"] != "true" || event.dig("amount", "value") != 0

        shopper_reference = event.dig("additionalData", "recurring.shopperReference")
        payment_method_id = event.dig("additionalData", "recurring.recurringDetailReference")
        customer = Customer.find_by(external_id: shopper_reference)

        payment_provider_customer = PaymentProviderCustomers::AdyenCustomer.find_by(customer:)
        payment_provider_customer.update!(provider_customer_id: shopper_reference)

        if organization.webhook_url?
          SendWebhookJob.perform_later('customer.payment_provider_created', customer)
        end

        result.raise_if_error! || result
      end
    end
  end
end
