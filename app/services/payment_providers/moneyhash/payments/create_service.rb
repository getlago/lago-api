# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    module Payments
      class CreateService < BaseService
        include ::Customers::PaymentProviderFinder

        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          PaymentRequests::Payments::MoneyhashService.new(@invoice).create
        end

        private

        attr_reader :payment, :reference, :metadata, :invoice, :provider_customer

        delegate :payment_provider, :customer, to: :provider_customer
      end
    end
  end
end
