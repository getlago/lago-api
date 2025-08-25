# frozen_string_literal: true

module Subscriptions
  class PlanUpgradeService < BaseService
    def initialize(current_subscription:, plan:, params:)
      @current_subscription = current_subscription
      @plan = plan

      @params = params
      @name = params[:name].to_s.strip
      super
    end

    def call
      if current_subscription.starting_in_the_future?
        update_pending_subscription

        result.subscription = current_subscription
        return result
      end

      new_subscription = new_subscription_with_overrides

      ActiveRecord::Base.transaction do
        cancel_pending_subscription if pending_subscription?

        # Group subscriptions for billing
        billable_subscriptions = billable_subscriptions(new_subscription)

        # Terminate current subscription as part of the upgrade process
        Subscriptions::TerminateService.call(
          subscription: current_subscription,
          upgrade: true
        )

        new_subscription.mark_as_active!
        after_commit do
          SendWebhookJob.perform_later("subscription.started", new_subscription)
          Utils::ActivityLog.produce(new_subscription, "subscription.started")
        end

        bill_subscriptions(billable_subscriptions) if billable_subscriptions.any?
      end

      result.subscription = new_subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :current_subscription, :plan, :params, :name

    def new_subscription_with_overrides
      new_subscription = Subscription.new(
        organization_id: current_subscription.customer.organization_id,
        customer: current_subscription.customer,
        plan: params.key?(:plan_overrides) ? plan_for_override_params(plan) : plan,
        name:,
        external_id: current_subscription.external_id,
        previous_subscription_id: current_subscription.id,
        subscription_at: current_subscription.subscription_at,
        billing_time: current_subscription.billing_time,
        ending_at: params.key?(:ending_at) ? params[:ending_at] : current_subscription.ending_at
      )
      create_fixed_charge_units_override(new_subscription) if overrides_only_fixed_charge_units?

      new_subscription
    end

    def update_pending_subscription
      current_subscription.plan = plan
      current_subscription.name = name if name.present?
      current_subscription.save!

      if current_subscription.should_sync_hubspot_subscription?
        Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription: current_subscription)
      end
    end

    def plan_for_override_params(plan)
      if overrides_only_fixed_charge_units?
        return plan
      end

      Plans::OverrideService.call(plan:, params: params[:plan_overrides].to_h.with_indifferent_access).plan
    end

    def overrides_only_fixed_charge_units?
      params[:plan_overrides] && params[:plan_overrides].keys == [:fixed_charges] &&
        params[:plan_overrides][:fixed_charges].map(&:keys).flatten.uniq.sort == [:id, :units]
    end

    def create_fixed_charge_units_override(subscription)
      params[:plan_overrides][:fixed_charges].each do |fixed_charge|
        FixedChargeUnitOverrideService.call!(
          subscription:,
          fixed_charge: subscription.plan.fixed_charges.find(fixed_charge[:id]),
          units: fixed_charge[:units]
        )
      end
    end

    def cancel_pending_subscription
      current_subscription.next_subscription.mark_as_canceled!
    end

    def pending_subscription?
      return false unless current_subscription.next_subscription

      current_subscription.next_subscription.pending?
    end

    def billable_subscriptions(new_subscription)
      billable_subscriptions = if current_subscription.starting_in_the_future?
        []
      elsif current_subscription.pending?
        []
      elsif !current_subscription.terminated?
        [current_subscription]
      end.to_a

      billable_subscriptions << new_subscription if plan.pay_in_advance? && !new_subscription.in_trial_period?

      billable_subscriptions
    end

    def bill_subscriptions(billable_subscriptions)
      after_commit do
        billing_at = Time.current + 1.second
        BillSubscriptionJob.perform_later(billable_subscriptions, billing_at.to_i, invoicing_reason: :upgrading)
        BillNonInvoiceableFeesJob.perform_later(billable_subscriptions, billing_at)
      end
    end
  end
end
