module Subscriptions
  class CreateSyncService < CreateService
    private

    def create_subscription
      new_subscription = Subscription.new(
        customer:,
        plan: params.key?(:plan_overrides) ? override_plan(plan) : plan,
        subscription_at:,
        name:,
        external_id:,
        billing_time: billing_time || :calendar,
        ending_at: params[:ending_at],
      )

      if new_subscription.subscription_at > Time.current
        new_subscription.pending!
      elsif new_subscription.subscription_at < Time.current
        new_subscription.mark_as_active!(new_subscription.subscription_at)
      else
        new_subscription.mark_as_active!
      end

      if new_subscription.active? && new_subscription.subscription_at.today? && plan.pay_in_advance?
        # TODO
        # before it was: perform_later(job_class: BillSubscriptionJob, arguments: [[new_subscription], Time.zone.now.to_i])
        # Have to handle retry logic same as in BillSubscriptionJob
        result = Invoices::SubscriptionSyncService.new(
          subscriptions: [new_subscription],
          timestamp:  Time.zone.now.to_i,
          recurring: false,
        ).create

        result.raise_if_error!
      end

      if new_subscription.active?
        perform_later(job_class: SendWebhookJob, arguments: ['subscription.started', new_subscription])
      end

      new_subscription
    end
  end
end