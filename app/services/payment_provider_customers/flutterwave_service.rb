# frozen_string_literal: true

module PaymentProviderCustomers
  class FlutterwaveService < BaseService
    include Customers::PaymentProviderFinder
    include TypedResults

    RESULTS = {
      create: BaseResult[:flutterwave_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult
    }.freeze

    private

    def create(flutterwave_customer)
      @flutterwave_customer = flutterwave_customer
      result.flutterwave_customer = flutterwave_customer
      result
    end

    def update(flutterwave_customer)
      @flutterwave_customer = flutterwave_customer
      result
    end

    def generate_checkout_url(flutterwave_customer, send_webhook: true)
      @flutterwave_customer = flutterwave_customer
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    attr_accessor :flutterwave_customer

    delegate :customer, to: :flutterwave_customer
  end
end
