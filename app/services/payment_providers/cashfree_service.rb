# frozen_string_literal: true

module PaymentProviders
  class CashfreeService < BaseService
    LINK_STATUS_ACTIONS = %w[PAID].freeze
    PAYMENT_ACTIONS = %w[SUCCESS FAILED USER_DROPPED CANCELLED VOID PENDING FLAGGED NOT_ATTEMPTED].freeze
    # REFUND_ACTIONS = %w[created funds_returned paid refund_settled failed].freeze

    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: 'cashfree'
      )

      cashfree_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::CashfreeProvider.new(
          organization_id: args[:organization].id,
          code: args[:code]
        )
      end

      cashfree_provider.client_id = args[:client_id] if args.key?(:client_id)
      cashfree_provider.client_secret = args[:client_secret] if args.key?(:client_secret)
      cashfree_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      cashfree_provider.code = args[:code] if args.key?(:code)
      cashfree_provider.name = args[:name] if args.key?(:name)
      cashfree_provider.save!

      result.cashfree_provider = cashfree_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def handle_incoming_webhook(organization_id:, body:, timestamp:, signature:, code: nil)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id:,
        code:,
        payment_provider_type: 'cashfree'
      )

      return payment_provider_result unless payment_provider_result.success?

      secret_key = payment_provider_result.payment_provider.client_secret
      data = "#{timestamp}#{body}"
      gen_signature = Base64.strict_encode64(OpenSSL::HMAC.digest('sha256', secret_key, data))

      unless gen_signature == signature
        return result.service_failure!(code: 'webhook_error', message: 'Invalid signature')
      end

      PaymentProviders::Cashfree::HandleEventJob.perform_later(event_json: body)

      result.event = body
      result
    end

    def handle_event(event_json:)
      event = JSON.parse(event_json)
      event_type = event['type']

      case event_type
      when 'PAYMENT_LINK_EVENT'
        link_status = event.dig('data', 'link_status')
        provider_payment_id = event.dig('data', 'link_notes', 'lago_invoice_id')

        if LINK_STATUS_ACTIONS.include?(link_status) && !provider_payment_id.nil?
          update_payment_status_result = Invoices::Payments::CashfreeService
            .new.update_payment_status(
              provider_payment_id: provider_payment_id,
              status: link_status
            )

          return update_payment_status_result unless update_payment_status_result.success?
        end
      end

      result.raise_if_error!
    end
  end
end
