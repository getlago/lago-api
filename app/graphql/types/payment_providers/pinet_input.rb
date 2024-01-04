# frozen_string_literal: true

module Types
  module PaymentProviders
    class PinetInput < BaseInputObject
      description 'Pinet input arguments'

      argument :create_customers, Boolean, required: false
      argument :secret_key, String, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
