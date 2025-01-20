# frozen_string_literal: true

module Plans
  class DestroyService < BaseService
    def initialize(plan:)
      @plan = plan
      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      # NOTE: Terminate active subscriptions.
      plan.subscriptions.active.find_each do |subscription|
        Subscriptions::TerminateService.call(subscription:, async: false)
      end

      # NOTE: Cancel pending subscription to make sure they won't be activated.
      plan.subscriptions.pending.find_each(&:mark_as_canceled!)

      # NOTE: Finalize all draft invoices.
      invoices = Invoice.draft.joins(:plans).where(plans: {id: plan.id}).distinct
      invoices.find_each { |invoice| Invoices::RefreshDraftAndFinalizeService.call(invoice:) }

      plan.pending_deletion = false
      plan.discard!

      result.plan = plan
      result
    end

    private

    attr_reader :plan
  end
end
