# frozen_string_literal: true

module PaymentProviders
  class GocardlessService < BaseService
    # NOTE: These links will be changed later
    AUTH_SITE = 'https://connect-sandbox.gocardless.com'
    REDIRECT_URI = "#{ENV['LAGO_OAUTH_PROXY_URL']}/gocardless/callback"
    PAYMENT_ACTIONS = %w[paid_out failed cancelled customer_approval_denied charged_back resubmission_requested].freeze

    def create_or_update(**args)
      access_token = oauth.auth_code.get_token(args[:access_code], redirect_uri: REDIRECT_URI)&.token

      gocardless_provider = PaymentProviders::GocardlessProvider.find_or_initialize_by(
        organization_id: args[:organization].id,
      )

      gocardless_provider.access_token = access_token if access_token
      gocardless_provider.webhook_secret = SecureRandom.alphanumeric(50)
      gocardless_provider.save!

      result.gocardless_provider = gocardless_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue OAuth2::Error => e
      result.service_failure!(code: 'internal_error', message: e.description)
    end

    def handle_incoming_webhook(organization_id:, body:, signature:)
      organization = Organization.find_by(id: organization_id)

      events = GoCardlessPro::Webhook.parse(
        request_body: body,
        signature_header: signature,
        webhook_endpoint_secret: organization&.gocardless_payment_provider&.webhook_secret,
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
      events = JSON.parse(events_json)['events']
      parsed_events = events.map { |event| GoCardlessPro::Resources::Event.new(event) }
      parsed_events.each do |event|
        case event.resource_type
        when 'payments'
          if PAYMENT_ACTIONS.include?(event.action)
            Invoices::Payments::GocardlessService
              .new.update_status(
                provider_payment_id: event.links.payment,
                status: event.action,
              )
          end
        end
      end
    end

    private

    def oauth
      OAuth2::Client.new(
        ENV['GOCARDLESS_CLIENT_ID'],
        ENV['GOCARDLESS_CLIENT_SECRET'],
        site: AUTH_SITE,
        authorize_url: '/oauth/authorize',
        token_url: '/oauth/access_token',
        auth_scheme: :request_body,
      )
    end
  end
end
