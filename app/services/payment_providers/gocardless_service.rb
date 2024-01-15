# frozen_string_literal: true

module PaymentProviders
  class GocardlessService < BaseService
    REDIRECT_URI = "#{ENV['LAGO_OAUTH_PROXY_URL']}/gocardless/callback".freeze
    PAYMENT_ACTIONS = %w[paid_out failed cancelled customer_approval_denied charged_back].freeze
    REFUND_ACTIONS = %w[created funds_returned paid refund_settled failed].freeze

    def create_or_update(**args)
      access_token = if args[:access_code].present?
        oauth.auth_code.get_token(args[:access_code], redirect_uri: REDIRECT_URI)&.token
      end

      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization].id,
        code: args[:code],
        id: args[:id],
        payment_provider_type: 'gocardless',
      )

      gocardless_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::GocardlessProvider.new(
          organization_id: args[:organization].id,
          code: args[:code],
        )
      end

      gocardless_provider.access_token = access_token if access_token
      gocardless_provider.webhook_secret = SecureRandom.alphanumeric(50) if gocardless_provider.webhook_secret.blank?
      gocardless_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      gocardless_provider.code = args[:code] if args.key?(:code)
      gocardless_provider.name = args[:name] if args.key?(:name)
      gocardless_provider.save!

      result.gocardless_provider = gocardless_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue OAuth2::Error => e
      result.service_failure!(code: 'internal_error', message: e.description)
    end

    def handle_incoming_webhook(organization_id:, body:, signature:, code: nil)
      payment_provider_result = PaymentProviders::FindService.call(organization_id:, code:)
      return payment_provider_result unless payment_provider_result.success?

      events = GoCardlessPro::Webhook.parse(
        request_body: body,
        signature_header: signature,
        webhook_endpoint_secret: payment_provider_result.payment_provider&.webhook_secret,
      )

      PaymentProviders::Gocardless::HandleEventJob.perform_later(events_json: body)

      result.events = events
      result
    rescue JSON::ParserError
      result.service_failure!(code: 'webhook_error', message: 'Invalid payload')
    rescue GoCardlessPro::Webhook::InvalidSignatureError
      result.service_failure!(code: 'webhook_error', message: 'Invalid signature')
    end

    def handle_event(events_json:)
      handled_events = []
      events = JSON.parse(events_json)['events']
      parsed_events = events.map { |event| GoCardlessPro::Resources::Event.new(event) }
      parsed_events.each do |event|
        case event.resource_type
        when 'payments'
          if PAYMENT_ACTIONS.include?(event.action)
            update_payment_status_result = Invoices::Payments::GocardlessService
              .new.update_payment_status(
                provider_payment_id: event.links.payment,
                status: event.action,
              )

            return update_payment_status_result unless update_payment_status_result.success?

            handled_events << event
          end
        when 'refunds'
          if REFUND_ACTIONS.include?(event.action)
            status_result = CreditNotes::Refunds::GocardlessService
              .new.update_status(
                provider_refund_id: event.links.refund,
                status: event.action,
              )

            return status_result unless status_result.success?

            handled_events << event
          end

        end
      end

      result.handled_events = handled_events
      result
    end

    private

    def oauth
      OAuth2::Client.new(
        ENV['GOCARDLESS_CLIENT_ID'],
        ENV['GOCARDLESS_CLIENT_SECRET'],
        site: PaymentProviders::GocardlessProvider.auth_site,
        authorize_url: '/oauth/authorize',
        token_url: '/oauth/access_token',
        auth_scheme: :request_body,
      )
    end
  end
end
