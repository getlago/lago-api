# frozen_string_literal: true

module Subscriptions
  class UpdateService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, params:)
      @subscription = subscription
      @params = params
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription },
      condition: -> { !subscription&.starting_in_the_future? },
      after_commit: true
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription

      unless valid?(
        customer: subscription.customer,
        plan: subscription.plan,
        subscription_at: params.key?(:subscription_at) ? params[:subscription_at] : subscription.subscription_at,
        ending_at: params[:ending_at],
        on_termination_credit_note: params[:on_termination_credit_note],
        on_termination_invoice: params[:on_termination_invoice]
      )
        return result
      end

      return result.forbidden_failure! if !License.premium? && params.key?(:plan_overrides)

      subscription.name = params[:name] if params.key?(:name)
      subscription.ending_at = params[:ending_at] if params.key?(:ending_at)

      if pay_in_advance? && params.key?(:on_termination_credit_note)
        subscription.on_termination_credit_note = params[:on_termination_credit_note]
      end

      if params.key?(:on_termination_invoice)
        subscription.on_termination_invoice = params[:on_termination_invoice]
      end

      if params.key?(:plan_overrides)
        plan_result = handle_plan_override
        return plan_result unless plan_result.success?

        subscription.plan = plan_result.plan
      end

      if subscription.starting_in_the_future? && params.key?(:subscription_at)
        subscription.subscription_at = params[:subscription_at]

        process_subscription_at_change(subscription)
      else
        subscription.save!

        SendWebhookJob.perform_after_commit("subscription.updated", subscription)

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_after_commit(subscription:)
        end
      end

      result.subscription = subscription
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :params

    def pay_in_advance?
      subscription.plan.pay_in_advance?
    end

    def process_subscription_at_change(subscription)
      if subscription.subscription_at <= Time.current
        subscription.mark_as_active!(subscription.subscription_at)

        EmitFixedChargeEventsService.call!(
          subscriptions: [subscription],
          timestamp: subscription.started_at
        )
      else
        subscription.save!
      end

      return unless subscription.plan.pay_in_advance? && subscription.subscription_at.today?

      BillSubscriptionJob.perform_after_commit([subscription], Time.current.to_i, invoicing_reason: :subscription_starting)
    end

    def handle_plan_override
      current_plan = subscription.plan

      if current_plan.parent_id
        Plans::UpdateService.call(
          plan: current_plan,
          params: params[:plan_overrides].to_h.with_indifferent_access
        )
      else
        Plans::OverrideService.call(
          plan: current_plan,
          params: params[:plan_overrides].to_h.with_indifferent_access,
          subscription:
        )
      end
    end

    def valid?(args)
      Subscriptions::ValidateService.new(result, **args).valid?
    end
  end
end
