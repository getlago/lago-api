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

      if new_subscription.payment_gated? && !new_subscription.in_trial_period?
        upgrade_with_payment_gating(new_subscription)
      else
        upgrade_immediately(new_subscription)
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

    def upgrade_with_payment_gating(new_subscription)
      ActiveRecord::Base.transaction do
        cancel_pending_subscription if pending_subscription?

        new_subscription.mark_as_activating!

        EmitFixedChargeEventsService.call!(
          subscriptions: [new_subscription],
          timestamp: new_subscription.started_at + 1.second
        )

        after_commit do
          BillSubscriptionJob.perform_later(
            [new_subscription],
            Time.zone.now.to_i,
            invoicing_reason: :upgrading
          )
          Subscriptions::ActivationTimeoutJob.set(
            wait_until: new_subscription.activation_timeout_at
          ).perform_later(new_subscription)
          SendWebhookJob.perform_later("subscription.activating", new_subscription)
          Utils::ActivityLog.produce(new_subscription, "subscription.activating")
        end
      end
    end

    def upgrade_immediately(new_subscription)
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

        EmitFixedChargeEventsService.call!(
          subscriptions: [new_subscription],
          timestamp: new_subscription.started_at + 1.second
        )

        after_commit do
          SendWebhookJob.perform_later("subscription.started", new_subscription)
          Utils::ActivityLog.produce(new_subscription, "subscription.started")
        end

        bill_subscriptions(billable_subscriptions) if billable_subscriptions.any?
      end
    end

    def new_subscription_with_overrides
      new_subscription = Subscription.new(
        organization_id: current_subscription.customer.organization_id,
        customer: current_subscription.customer,
        plan: params.key?(:plan_overrides) ? override_plan : plan,
        name:,
        external_id: current_subscription.external_id,
        previous_subscription_id: current_subscription.id,
        subscription_at: current_subscription.subscription_at,
        billing_time: current_subscription.billing_time,
        ending_at: params.key?(:ending_at) ? params[:ending_at] : current_subscription.ending_at,
        activation_rules: params.key?(:activation_rules) ? params[:activation_rules] : current_subscription.activation_rules
      )

      if params.key?(:payment_method)
        new_subscription.payment_method_type = params[:payment_method][:payment_method_type] if params[:payment_method].key?(:payment_method_type)
        new_subscription.payment_method_id = params[:payment_method][:payment_method_id] if params[:payment_method].key?(:payment_method_id)
      end

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

    def override_plan
      Plans::OverrideService.call(plan:, params: params[:plan_overrides].to_h.with_indifferent_access).plan
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

      has_billable_fixed_charges = new_subscription.fixed_charges.pay_in_advance.any?
      plan_billable = new_subscription.plan.pay_in_advance? && !new_subscription.in_trial_period?

      billable_subscriptions << new_subscription if has_billable_fixed_charges || plan_billable

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
