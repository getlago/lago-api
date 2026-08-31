# frozen_string_literal: true

module Payments
  class OpenDisputeService < BaseService
    Result = BaseResult[:invoices, :payment]

    def initialize(payment:, payment_refund_blocked_at: nil)
      @payment = payment
      @payable = payment&.payable
      @payment_refund_blocked_at = payment_refund_blocked_at.presence || Time.current
      super
    end

    def call
      return result.not_found_failure!(resource: "payment") if payment.nil?
      return result.not_found_failure!(resource: "payable") if payable.nil?

      result.payment = payment
      invoices = payment.invoices

      ActiveRecord::Base.transaction do
        invoices.each do |invoice|
          # NOTE: a lost dispute already blocks refunds permanently. Skipping it keeps an
          #       out-of-order `created` event from reopening a settled dispute.
          next if invoice.payment_dispute_lost_at?

          invoice.mark_refund_as_blocked!(payment_refund_blocked_at)
        end
      end

      result.invoices = invoices
      result
    end

    private

    attr_reader :payment, :payable, :payment_refund_blocked_at
  end
end
