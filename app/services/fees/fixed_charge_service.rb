# frozen_string_literal: true

module Fees
  class FixedChargeService < BaseService
    def initialize(invoice:, fixed_charge:, subscription:, boundaries:, context: nil)
      @invoice = invoice
      @fixed_charge = fixed_charge
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)
      @currency = subscription.plan.amount.currency
      @context = context

      super
    end

    def call
      result
    end
  end
end
