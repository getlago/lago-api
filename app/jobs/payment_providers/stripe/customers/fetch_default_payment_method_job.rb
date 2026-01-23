# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Customers
      class FetchDefaultPaymentMethodJob < ApplicationJob
        queue_as :default

        def perform(provider_customer)
          PaymentProviders::Stripe::Customers::FetchDefaultPaymentMethodService.call!(provider_customer:)
        end
      end
    end
  end
end
