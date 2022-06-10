# frozen_string_literal: true

module Types
  module PaymentProviders
    class Stripe < Types::BaseObject
      graphql_name 'StripeProvider'

      field :id, ID, null: false
      field :public_key, String, null: false

      field :create_customers, Boolean, null: false
      field :send_zero_amount_invoice, Boolean, null: false
    end
  end
end
