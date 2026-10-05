# frozen_string_literal: true

module PaymentTerms
  class ResolveService < BaseService
    Result = BaseResult[:payment_term, :source]

    DEFAULT_TERM = {"term_type" => "due_on_receipt"}.freeze

    def initialize(customer:, billing_entity: nil)
      @customer = customer
      @billing_entity = billing_entity
      super
    end

    def call
      if customer.payment_term.present?
        result.payment_term = PaymentTerm.from_h(customer.payment_term)
        result.source = "customer"
      elsif issuing_billing_entity.payment_term.present?
        result.payment_term = PaymentTerm.from_h(issuing_billing_entity.payment_term)
        result.source = "billing_entity"
      else
        result.payment_term = PaymentTerm.from_h(DEFAULT_TERM)
        result.source = "default"
      end

      result
    end

    private

    attr_reader :customer, :billing_entity

    def issuing_billing_entity
      billing_entity || customer.billing_entity
    end
  end
end
