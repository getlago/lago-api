# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    def api_key=(api_key)
      push_to_secrests({ api_key: api_key })
    end

    def api_key
      get_from_secrets(:api_key)
    end

    def secret_key=(secret_key)
      push_to_secrests({ secret_key: secret_key })
    end

    def secret_key
      get_from_secrets(:api_key)
    end
  end
end
