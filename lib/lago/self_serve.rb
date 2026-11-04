# frozen_string_literal: true

module Lago
  # Cloud self-serve signup (verified email signup, sandbox organizations). Self-hosted leaves
  # LAGO_SELF_SERVE_ENABLED unset, which keeps the single-screen signup.
  module SelfServe
    ENV_VAR = "LAGO_SELF_SERVE_ENABLED"
    ACCEPTED_VALUES = ["", "true", "false"].freeze

    class << self
      # Only "true" turns the gate on (any case, surrounding spaces ignored): a security gate errs toward off.
      def enabled?(value: ENV[ENV_VAR])
        normalize(value) == "true"
      end

      # Exactly "true", as the API and lago-front have always read LAGO_DISABLE_SIGNUP. With the gate on,
      # validate! refuses other spellings, which would leave signup open.
      def signup_disabled?(value: ENV["LAGO_DISABLE_SIGNUP"])
        value == "true"
      end

      # Run at boot: a malformed value stops the deploy instead of leaving the gate off, and a region never
      # sends verification links, Google redirects or captcha checks to the default US front.
      def validate!(
        value: ENV[ENV_VAR],
        front_url: ENV["LAGO_FRONT_URL"],
        disable_signup: ENV["LAGO_DISABLE_SIGNUP"],
        local: Rails.env.local?
      )
        unless ACCEPTED_VALUES.include?(normalize(value))
          raise ArgumentError, "#{ENV_VAR} must be true or false, got #{value.inspect}"
        end

        if enabled?(value:) && !valid_front_url?(front_url, local:)
          raise ArgumentError,
            "LAGO_FRONT_URL must be the https origin of this region's front, such as https://app.getlago.com, " \
            "when #{ENV_VAR} is true; got #{front_url.inspect}"
        end

        # Self-hosted keeps reading any other spelling as off, as it always has.
        if enabled?(value:) && !ACCEPTED_VALUES.include?(disable_signup.to_s)
          raise ArgumentError,
            "LAGO_DISABLE_SIGNUP must be exactly true or false when #{ENV_VAR} is true; got #{disable_signup.inspect}"
        end
      end

      private

      def normalize(value) = value.to_s.strip.downcase

      # Development and test fall back to a local front and accept http.
      def valid_front_url?(url, local:)
        if url.blank?
          local
        else
          origin?(url, schemes: local ? %w[http https] : %w[https])
        end
      end

      # Written exactly as LagoApi::Application.origin_of renders it, which is also the Origin header browsers send.
      def origin?(url, schemes:)
        uri = URI.parse(url)

        schemes.include?(uri.scheme) && uri.host.present? && url == LagoApi::Application.origin_of(url)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
