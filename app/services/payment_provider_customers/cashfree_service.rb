# frozen_string_literal: true

module PaymentProviderCustomers
  class CashfreeService < BaseService
    include Customers::PaymentProviderFinder
    include TypedResults

    RESULTS = {
      create: BaseResult[:cashfree_customer],
      update: BaseResult,
      generate_checkout_url: BaseResult
    }.freeze

    private

    def create(cashfree_customer)
      @cashfree_customer = cashfree_customer
      result.cashfree_customer = cashfree_customer
      result
    end

    def update(cashfree_customer)
      @cashfree_customer = cashfree_customer
      result
    end

    def generate_checkout_url(cashfree_customer, send_webhook: true)
      @cashfree_customer = cashfree_customer
      result.not_allowed_failure!(code: "feature_not_supported")
    end

    attr_accessor :cashfree_customer

    delegate :customer, to: :cashfree_customer
  end
end
