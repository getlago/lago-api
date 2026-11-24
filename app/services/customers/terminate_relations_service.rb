# frozen_string_literal: true

module Customers
  class TerminateRelationsService < BaseService
    Result = BaseResult[:customer]

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

      if BillingEngineMigrations::Lookup.shadow_organization?(customer.organization_id)
        terminate_contracts
        delete_draft_invoices
      else
        # NOTE: Finalize all draft invoices.
        customer.invoices.draft.find_each { |invoice| Invoices::FinalizeJob.set(wait: 5.minutes).perform_later(invoice) }
      end

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

    def terminate_contracts
      customer.contracts.live.find_each { |contract| Contracts::TerminateService.call(contract:) }
    end

    def delete_draft_invoices
      customer.invoices.draft.find_each do |invoice|
        delete_result = Invoices::DeleteService.call(invoice:)

        if delete_result.failure?
          Rails.logger.warn(
            "Customers::TerminateRelationsService: draft invoice #{invoice.id} not deleted: #{delete_result.error.code}"
          )
        end
      end
    end
  end
end
