# frozen_string_literal: true

module PaymentTerms
  class ResolveService < BaseService
    Result = BaseResult[:payment_term, :source]

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      if customer.payment_term.present?
        result.payment_term = PaymentTerm.from_h(customer.payment_term)
        result.source = "customer"
      elsif customer.billing_entity.payment_term.present?
        result.payment_term = PaymentTerm.from_h(customer.billing_entity.payment_term)
        result.source = "billing_entity"
      else
        result.payment_term = PaymentTerm.new(term_type: "due_on_receipt")
        result.source = "default"
      end

      result
    end

    private

    attr_reader :customer
  end
end
