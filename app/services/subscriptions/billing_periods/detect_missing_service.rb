# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Finds the active subscriptions of an organization left without a period covering now, and
    # re-derives them.
    #
    # A non-zero count is a bug rather than routine: the periods are maintained by the services that
    # move a subscription's billing dates, so a subscription without one means a path is missing its
    # call. This is the only net under those hooks, which is why it reports as well as heals.
    class DetectMissingService < BaseService
      Result = BaseResult[:missing_count]

      def initialize(organization:)
        @organization = organization

        super
      end

      def call
        result.missing_count = 0
        return result if organization.feature_flag_disabled?(:subscription_billing_periods)

        count = 0
        subscriptions_without_period.find_each do |subscription|
          Subscriptions::BillingPeriods::UpsertJob.perform_later(subscription.id)
          count += 1
        end

        result.missing_count = count
        report(count)
        result
      end

      private

      attr_reader :organization

      def subscriptions_without_period
        organization.subscriptions.active.where.not(
          SubscriptionBillingPeriod
            .covering(Time.current)
            .where("subscription_billing_periods.subscription_id = subscriptions.id")
            .arel.exists
        )
      end

      def report(count)
        return if count.zero?

        Rails.logger.warn(
          "[billing_periods] #{count} active subscriptions without a covering period " \
          "organization_id=#{organization.id}"
        )
      end
    end
  end
end
