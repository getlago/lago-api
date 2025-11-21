# frozen_string_literal: true

module Invoices
  class IssuingDateService
    def initialize(customer:, billing_entity: nil, recurring: false)
      @customer = customer
      @billing_entity = billing_entity || customer.try(:billing_entity) || {}
      @recurring = recurring
    end

    def issuing_date_adjustment
      return grace_period unless recurring

      send("#{anchor}_#{adjustment}")
    end

    private

    attr_reader :customer, :billing_entity, :recurring

    def current_period_end_keep_anchor
      -1
    end

    def current_period_end_align_with_finalization_date
      grace_period
    end

    def next_period_start_keep_anchor
      0
    end

    def next_period_start_align_with_finalization_date
      grace_period
    end

    def grace_period
      customer[:invoice_grace_period] || billing_entity[:invoice_grace_period] || 0
    end

    def anchor
      customer[:subscription_invoice_issuing_date_anchor] || billing_entity[:subscription_invoice_issuing_date_anchor]
    end

    def adjustment
      customer[:subscription_invoice_issuing_date_adjustment] || billing_entity[:subscription_invoice_issuing_date_adjustment]
    end
  end
end
