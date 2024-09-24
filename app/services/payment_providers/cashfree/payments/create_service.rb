# frozen_string_literal: true

module PaymentProviders
  module Cashfree
    module Payments
      class CreateService < BaseService
        include Customers::PaymentProviderFinder

        PENDING_STATUSES = %w[PARTIALLY_PAID].freeze
        SUCCESS_STATUSES = %w[PAID].freeze
        FAILED_STATUSES = %w[EXPIRED CANCELLED].freeze

        def initialize(payment:)
          @payment = payment
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment
          result
        end

        private

        attr_reader :payment, :invoice, :provider_customer

        delegate :payment_provider, :customer, to: :provider_customer
      end
    end
  end
end
