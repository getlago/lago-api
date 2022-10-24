# frozen_string_literal: true

module PaymentProviders
  class GocardlessService < BaseService
    # NOTE: These links will be changed later
    AUTH_SITE = 'https://connect-sandbox.gocardless.com'
    REDIRECT_URI = 'https://proxy.lago.dev/gocardless/callback'

    def create_or_update(**args)
      access_token = oauth.auth_code.get_token(args[:access_code], redirect_uri: REDIRECT_URI)&.token

      gocardless_provider = PaymentProviders::GocardlessProvider.find_or_initialize_by(
        organization_id: args[:organization].id,
      )

      gocardless_provider.access_token = access_token if access_token
      gocardless_provider.save!

      result.gocardless_provider = gocardless_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue OAuth2::Error => e
      result.service_failure!(code: 'unauthorized', message: e.description)
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
