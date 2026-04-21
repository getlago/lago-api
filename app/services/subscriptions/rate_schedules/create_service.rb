# frozen_string_literal: true

module Subscriptions
  module RateSchedules
    class CreateService < BaseService
      Result = BaseResult[:subscription, :payment_method]

      def initialize(customer:, plan:, params:)
        super

        @customer = customer
        @plan = plan
        @params = params

        @name = params[:name].to_s.strip
        @subscription_at = params[:subscription_at] || Time.current
      end

      def call
        ActiveRecord::Base.transaction do
          subscription = create_subscription

          emit_events(subscription)
          bill_subscription(subscription)
          log_and_send_webhooks(subscription)
          sync_with_hubspot(subscription)
        end

        result.subscription = subscription
        result
      end

      private

      attr_reader :customer,
        :plan,
        :params,
        :name,
        :subscription_at,

      def create_subscription
        subscription = build_subscription

        if subscription.subscription_at > Time.current
          subscription.pending!
        elsif subscription.subscription_at < Time.current
          subscription.mark_as_active!(subscription.subscription_at)
        else
          subscription.mark_as_active!
        end

        subscription
      end

      def build_subscription
        Subscription.new(
          organization_id: customer.organization_id,
          customer:,
          plan:,
          subscription_at:,
          name:,
          external_id: params[:external_id],
          billing_time: params[:billing_time] || :calendar,
          ending_at: params[:ending_at],
          progressive_billing_disabled: params[:progressive_billing_disabled] || false,
          **payment_method_params
        )
      end

      def payment_method_params
        return {} unless if params[:payment_method]

        {
          payment_method_type: params[:payment_method][:payment_method_type],
          payment_method_id: params[:payment_method][:payment_method_id]
        }.compact_blank
      end

      def emit_events
        return unless subscription.active?

        EmitFixedChargeEventsService.call!(
          subscriptions: [subscription],
          timestamp: subscription.started_at + 1.second
        )

        after_commit do
          if fixed_charges_billed_today?(subscription)
            Invoices::CreatePayInAdvanceFixedChargesJob.perform_later(
              subscription,
              subscription.started_at + 1.second
            )
          end
        end
      end

      def bill_subscription(subscription)
        if should_be_billed_today?(subscription)
          # NOTE: Since job is launched from inside a db transaction
          #       we must wait for it to be committed before processing the job.
          #       We do not set offset anymore but instead retry jobs
          after_commit do
            BillSubscriptionJob.perform_later(
              [subscription],
              Time.zone.now.to_i,
              invoicing_reason: :subscription_starting,
              skip_charges: true
            )
          end
        end
      end

      def should_be_billed_today?(sub)
        sub.active? && sub.subscription_at.today? && plan.pay_in_advance? && !sub.in_trial_period?
      end

      def fixed_charges_billed_today?(sub)
        return false if !(sub.active? && sub.started_at.today?)
        return false if sub.fixed_charges.pay_in_advance.none?

        !sub.plan.pay_in_advance? || sub.in_trial_period?
      end

      def log_and_send_webhooks(subscription)
        return unless subscription.active?

        after_commit do
          SendWebhookJob.perform_later("subscription.started", subscription)
          Utils::ActivityLog.produce(subscription, "subscription.started")
        end
      end

      def sync_with_hubspot(subscription)
        return unless subscription.should_sync_hubspot_subscription?

        after_commit { Integrations::Aggregator::Subscriptions::Hubspot::CreateJob.perform_later(subscription:) }
      end

      def payment_method
        return @payment_method if defined? @payment_method
        return nil if params[:payment_method].blank? || params[:payment_method][:payment_method_id].blank?

        @payment_method = PaymentMethod.find_by(id: params[:payment_method][:payment_method_id], organization_id: customer.organization_id)
      end
    end
  end
end
