# frozen_string_literal: true

module Fees
  class RegroupingChargeService < BaseService
    Result = BaseResult[:regrouping_charge]

    def initialize(billing_contexts:)
      @billing_contexts = billing_contexts
      super
    end

    def call
      result.regrouping_charge = Charge.where(
        plan_id: billing_contexts.filter_map(&:plan_id).uniq,
        pay_in_advance: true,
        invoiceable: false,
        regroup_paid_fees: :invoice
      ).exists?
      result
    end

    private

    attr_reader :billing_contexts
  end
end
