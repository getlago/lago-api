# frozen_string_literal: true

module Types
  module PaymentProviders
    class UpdateInput < BaseInputObject
      description 'Stripe input arguments'

      argument :code, String, required: false
      argument :name, String, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
