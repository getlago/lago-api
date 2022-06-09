# frozen_string_literal: true

module Types
  module PaymentProviders
    class Stripe < Types:: BaseObject
      graphql_name 'StripeProvider'

      field :id, ID, null: false
      field :api_key, String, null: false
    end
  end
end
