# frozen_string_literal: true

module Customers
  class TerminateRelationsService < BaseService
    def initialize(customer:)
      @customer = customer
      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      # NOTE: Terminate active subscriptions.
      customer.subscriptions.active.find_each do |subscription|
        Subscriptions::TerminateService.call(subscription:, async: false)
      end

      # NOTE: Cancel pending subscriptions
      customer.subscriptions.pending.find_each(&:mark_as_canceled!)

      # NOTE: Finalize all draft invoices.
      customer.invoices.draft.find_each { |invoice| Invoices::FinalizeJob.set(wait: 5.minutes).perform_later(invoice) }

      # NOTE: Terminate applied coupons
      customer.applied_coupons.active.find_each do |applied_coupon|
        AppliedCoupons::TerminateService.call(applied_coupon:)
      end

      # NOTE: Terminate wallets
      customer.wallets.active.find_each { |wallet| Wallets::TerminateService.call(wallet:) }

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end

we have added fixed charges to plan. Now during the billing process (BillSubscriptionJob) we'd generate a new invoice subscription and all fees for this subscription
Invoice subscription have boundaries: from/to is responsible for subscription period. Charges_from/to - responsible for period for when the usage-based charges are applied
But also now we'll have fixed_charges from/to - also responsible for fixed charges billing period. It works fine for monthly billing cycle when all periods are aligned, but if we have different billing cycles (e.g. monthly subscription with quarterly fixed charges), we have a problem:
in the invoice_subscription from/to is a year, charges from/to is a year, whle fixed_charges from/to is just a month, and this is repeated for every month of the billing period.
But since we have a uniqueness validation on subscription_id, charges_from. charges_to, this will fail. Similarly it will fail if we introduce
similar uniqueness index on fixed_charges from/to and charges billed monthly.

if you were a software architect, who works in the best companies with the best architecture, who follows all the software design principles and cares about making a system that is enjoyment to work with, as an engineer,
which solutions would you suggest?