# frozen_string_literal: true

module Types
  module PaymentProviders
    class StripeInput < BaseInputObject
      description 'Stripe input arguments'

      argument :create_customers, Boolean, required: false
      argument :error_redirect_url, String, required: false
      argument :secret_key, String, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
