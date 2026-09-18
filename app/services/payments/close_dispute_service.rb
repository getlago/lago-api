# frozen_string_literal: true

module Payments
  class CloseDisputeService < BaseService
    Result = BaseResult[:invoices, :payment]

    def initialize(payment:)
      @payment = payment
      @payable = payment&.payable
      super
    end

    def call
      return result.not_found_failure!(resource: "payment") if payment.nil?
      return result.not_found_failure!(resource: "payable") if payable.nil?

      result.payment = payment
      invoices = payment.invoices

      ActiveRecord::Base.transaction do
        invoices.each(&:mark_refund_as_unblocked!)
      end

      result.invoices = invoices
      result
    end

    private

    attr_reader :payment, :payable
  end
end
