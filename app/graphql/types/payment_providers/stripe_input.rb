# frozen_string_literal: true

module Types
  module PaymentProviders
    class StripeInput < BaseInputObject
      description "Stripe input arguments"

      argument :code, String, required: true
      argument :name, String, required: true
      argument :require_terms_of_service_consent, Boolean, required: false
      argument :secret_key, String, required: false
      argument :success_redirect_url, String, required: false
      argument :supports_3ds, Boolean, required: false
    end
  end
end
