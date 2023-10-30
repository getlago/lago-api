# frozen_string_literal: true

module Types
  module PaymentProviders
    class GocardlessInput < BaseInputObject
      description 'Gocardless input arguments'

      argument :access_code, String, required: false
      argument :success_redirect_url, String, required: false
    end
  end
end
