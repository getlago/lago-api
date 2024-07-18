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
      track_plan_deleted

      result.plan = plan
      result
    end

    private

    attr_reader :plan

    def track_plan_deleted
      count_by_charge_model = plan.charges.group(:charge_model).count

      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'plan_deleted',
        properties: {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: plan.pay_in_advance ? 'advance' : 'arrears',
          trial: plan.trial_period,
          nb_charges: plan.charges.count,
          nb_standard_charges: count_by_charge_model['standard'] || 0,
          nb_percentage_charges: count_by_charge_model['percentage'] || 0,
          nb_graduated_charges: count_by_charge_model['graduated'] || 0,
          nb_package_charges: count_by_charge_model['package'] || 0,
          organization_id: plan.organization_id
        }
      )
    end
  end
end
