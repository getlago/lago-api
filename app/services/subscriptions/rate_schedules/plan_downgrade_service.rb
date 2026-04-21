# frozen_string_literal: true

module Subscriptions
  module RateSchedules
    class PlanDowngradeService < BaseService
      Result = BaseResult[:subscription]

      def initialize(subscription:, plan:, params:)
        @subscription = subscription
        @plan = plan
        @params = params

        super
      end

      def call
        if subscription.starting_in_the_future?
          downgrade_pending_subscription
        else
          downgrade_active_subscription
        end

        result
      end

      private

      attr_reader :subscription, :plan, :params

      def downgrade_pending_subscription
        subscription.plan = plan
        subscription.name = params[:name] if params[:name].present?
        subscription.save!

        if subscription.should_sync_hubspot_subscription?
          Integrations::Aggregator::Subscriptions::Hubspot::UpdateJob.perform_later(subscription:)
        end

        result.subscription = subscription
      end

      # NOTE: When downgrading a subscription, we keep the current one active
      #       until the next billing day. The new subscription will become active at this date
      def downgrade_active_subscription
        cancel_next_susbcription if next_subscription_pending?

        new_subscription = create_next_subscription
        InvoiceCustomSections::AttachToResourceService.call(resource: new_subscription, params:)

        after_commit do
          SendWebhookJob.perform_later("subscription.updated", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.updated")
        end

        result.subscription = new_subscription
      end

      def next_subscription_pending?
        return false unless subscription&.next_subscription

        subscription.next_subscription.pending?
      end

      def cancel_next_susbcription
        subscription.next_subscription.mark_as_canceled!
      end

      def create_next_subscription
        subscription.next_subscriptions.create!(
          organization_id: customer.organization_id,
          customer:,
          plan:,
          name:,
          status: :pending,
          external_id: subscription.external_id,
          subscription_at: subscription.subscription_at,
          billing_time: subscription.billing_time,
          ending_at: params[:ending_at] || subscription.ending_at,
          progressive_billing_disabled: params[:progressive_billing_disabled] || false,
          **payment_method_params
        )
      end

      def payment_method_params
        return {} unless params[:payment_method]

        {
          payment_method_type: params[:payment_method][:payment_method_type],
          payment_method_id: params[:payment_method][:payment_method_id]
        }.compact_blank
      end
    end
  end
end
