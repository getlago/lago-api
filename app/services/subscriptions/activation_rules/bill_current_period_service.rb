# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class BillCurrentPeriodService < BaseService
      Result = BaseResult

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        return result unless subscription.active?
        return result if subscription.previous_subscription
        return result unless subscription.activation_rules.payment.any?
        return result if billing_at <= subscription.started_at
        return result if already_billed?

        BillSubscriptionJob.perform_later([subscription], billing_at.to_i, invoicing_reason: :subscription_periodic)

        result
      end

      private

      attr_reader :subscription

      def already_billed?
        boundaries = Subscriptions::DatesService.new_instance(subscription, billing_at, current_usage: false)

        InvoiceSubscription.matching?(subscription, boundaries)
      end

      # Beginning of the period in progress, which is the boundary tick the
      # billing clock would have used to bill it. Yearly and semiannual plans
      # with monthly-billed charges or fixed charges are billed by the clock at
      # every monthly split boundary, so the split window applies instead.
      def billing_at
        @billing_at ||= begin
          dates = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)

          if subscription.plan.charges_billed_in_monthly_split_intervals?
            dates.charges_from_datetime
          elsif subscription.plan.fixed_charges_billed_in_monthly_split_intervals?
            dates.fixed_charges_from_datetime
          else
            dates.previous_beginning_of_period(current_period: true)
          end
        end
      end
    end
  end
end
