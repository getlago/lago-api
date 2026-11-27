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

      # NOTE: Terminate applied coupons
      customer.applied_coupons.active.find_each do |applied_coupon|
        AppliedCoupons::TerminateService.call(applied_coupon:)
      end

      # NOTE: Terminate wallets
      customer.wallets.active.find_each { |wallet| Wallets::TerminateService.call(wallet:) }

      if shadow_organization?
        terminate_contracts
        delete_draft_invoices
      else
        # NOTE: Finalize all draft invoices.
        customer.invoices.draft.find_each { |invoice| Invoices::FinalizeJob.set(wait: 5.minutes).perform_later(invoice) }
      end

      result.customer = customer
      result
    end

    private

    attr_reader :customer

    def shadow_organization?
      migration = BillingEngineMigrations::Lookup.for_shadow(customer.organization_id)
      return false unless migration

      migration.shadowing? || migration.paused?
    end

    def terminate_contracts
      timestamp = customer.deleted_at || Time.current

      customer.contracts.live.includes(:customer).find_each do |contract|
        termination = Contracts::TerminateService.call(contract:, timestamp:)
        termination.raise_if_error! unless termination.success? || already_terminated?(termination.error)
      end
    end

    def already_terminated?(error)
      error.is_a?(BaseService::ValidationFailure) && Array(error.messages[:contract]).include?("cannot_terminate")
    end

    # A billing run in progress holds this lock while it builds drafts: waiting for it keeps them from escaping the deletion.
    def delete_draft_invoices
      Customers::LockService.call!(customer:, scope: :billing_schedule, transaction: false) do
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
end
