# frozen_string_literal: true

module Omniauth
  module Strategies
    class Boxyhqsso < OmniAuth::Strategies::OAuth2
      option :name, :boxyhqsso

      args %i[
        client_id
        client_secret
        domain
      ]

      uid { raw_info['id'] }

      def client
        options.client_options.site = domain_url
        options.client_options.authorize_url = '/oauth/authorize'
        options.client_options.token_url = '/oauth/token'
        options.client_options.user_info_url = '/api/v1/users/me'
        options.client_options.auth_scheme = :request_body
        options.token_params = { redirect_uri: "#{full_host}auth/boxyhqsso/callback" }
      end

      def authorize_params
        params = super
        %w[
          connection
          connection_scope
          prompt
          screen_hint
          login_hint
          organization
          invitation
          ui_locales
          tenant
          product
        ].each do |key|
          params[key] = request.params[key] if request.params.key?(key)
        end

        params[:nonce] = SecureRandom.hex
        session['authorize_params'] = params.to_hash

        params
      end

      extra do
        {
          'raw_info' => raw_info,
        }
      end

      def request_phase
        fail!(:missing_client_id) if options.client_id.blank?
        fail!(:missing_client_secret) if options.client_secret.blank?
        fail!(:missing_domain) if options.domain.blank?

        super
      end

      def raw_info
        userinfo_url = options.client_options.user_info_url
        @raw_info ||= access_token.get(userinfo_url).parsed
      end

      def domain_url
        domain_url = URI(options.domain)
        domain_url = URI("https://#{options.domain}") if domain_url.scheme.nil?
        domain_url.to_s
      end
    end
  end
end
