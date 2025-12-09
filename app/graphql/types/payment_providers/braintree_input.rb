# frozen_string_literal: true

module Types
  module PaymentProviders
    class BraintreeInput < BaseInputObject
      description "Braintree input arguments"

      argument :code, String, required: true
      argument :merchant_id, String, required: true
      argument :name, String, required: true
      argument :private_key, String, required: true
      argument :public_key, String, required: true
      argument :success_redirect_url, String, required: false
    end
  end
end
