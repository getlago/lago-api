# frozen_string_literal: true

module Customers
  class TerminateRelationsService < BaseService
    def self.call(...)
      new(...).call
    end

    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      return result.not_allowed_failure!(resource: 'customer') unless customer

      # NOTE: Terminate active subscriptions.
      customer.subscriptions.active.each do |subscription|
        Subscriptions::TerminateService.call(subscription:, async: false)
      end

      # NOTE: Cancel pending subscriptions
      customer.subscriptions.pending.each(&:mark_as_canceled!)

      # NOTE: Finalize all draft invoices.
      customer.invoices.draft.each { |invoice| Invoices::FinalizeService.call(invoice:) }

      # NOTE: Terminate applied coupons
      customer.applied_coupons.active.each { |applied_coupon| AppliedCoupons::TerminateService.call(applied_coupon:) }

      # NOTE: Terminate wallets
      customer.wallets.active.each { |wallet| Wallets::TerminateService.call(wallet:) }

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end
