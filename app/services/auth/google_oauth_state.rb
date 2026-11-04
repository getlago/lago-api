# frozen_string_literal: true

module Auth
  # Binds a Google OAuth flow to the tab that started it, without storage: the state and the PKCE verifier are HMACs of
  # a secret only that tab keeps, which stops login CSRF and the redemption of a leaked code.
  module GoogleOauthState
    TTL = 10.minutes
    CLOCK_SKEW = 1.minute
    MAX_LENGTH = 128

    Issued = Data.define(:state, :secret, :code_verifier)

    module_function

    def issue
      secret = SecureRandom.urlsafe_base64(32)
      issued_at = Time.current.to_i

      Issued.new(state: "#{issued_at}.#{signature(issued_at, secret)}", secret:, code_verifier: code_verifier(secret))
    end

    # The PKCE code verifier of the flow, or nil when the state was not issued with this secret.
    def verify(state:, secret:)
      return if state.blank? || secret.blank? || state.length > MAX_LENGTH || secret.length > MAX_LENGTH

      issued_at, sig = state.split(".", 2)
      return unless issued_at.match?(/\A\d{1,12}\z/) && sig.present?

      fresh = (Time.current.to_i - issued_at.to_i).between?(-CLOCK_SKEW.to_i, TTL.to_i)
      code_verifier(secret) if fresh && ActiveSupport::SecurityUtils.secure_compare(sig, signature(issued_at.to_i, secret))
    end

    # The front URL is signed too, so a state from one region never verifies in the other.
    def signature(issued_at, secret)
      OpenSSL::HMAC.hexdigest("SHA256", key, "state|#{Rails.application.config.lago_front_url}|#{issued_at}|#{secret}")
    end

    # 43 characters of the RFC 7636 alphabet.
    def code_verifier(secret)
      Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", key, "pkce|#{secret}"), padding: false)
    end

    def key
      Rails.application.key_generator.generate_key("lago.google_oauth_state", 32)
    end

    private_class_method :signature, :code_verifier, :key
  end
end
