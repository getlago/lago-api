# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Finds the subscriptions of an organization left without the period they should have, and
    # re-derives them.
    #
    # A non-zero count is a bug rather than routine: the periods are maintained by the services that
    # move a subscription's billing dates, so a subscription without one means a path is missing its
    # call. This is the only net under those hooks, which is why it reports as well as heals.
    #
    # Two populations, two probes, reported apart so that each stays a clean zero-signal: an active
    # subscription must have a period covering now, and a recently terminated one must have its final
    # period.
    class DetectMissingService < BaseService
      Result = BaseResult[:missing_count]

      def initialize(organization:)
        @organization = organization

        super
      end

      def call
        result.missing_count = 0
        return result if organization.feature_flag_disabled?(:subscription_billing_periods)

        active_count = heal(active_subscriptions_without_period)
        terminated_count = heal(terminated_subscriptions_without_period)

        result.missing_count = active_count + terminated_count
        report(active_count, "active subscriptions without a covering period")
        report(terminated_count, "terminated subscriptions without their final period")
        result
      end

      private

      attr_reader :organization

      def heal(scope)
        count = 0
        scope.find_each do |subscription|
          Subscriptions::BillingPeriods::UpsertJob.perform_later(subscription.id)
          count += 1
        end

        count
      end

      # Mirrors Subscriptions::BillingPeriods::UpsertService#skip?, which is what makes a non-zero
      # count a bug: a subscription the writer refuses to write for is not missing anything, and
      # reporting it turns the count into a number that never reaches zero.
      #
      # A plan without an interval has no period to derive — a product catalog plan is not required
      # to have one — and a subscription that has yet to start has its first period stored ahead of
      # now, so nothing covers now until it does.
      def derivable_subscriptions
        organization.subscriptions
          .joins(:plan)
          .where.not(plans: {interval: nil})
          .where(started_at: ..Time.current)
      end

      def active_subscriptions_without_period
        derivable_subscriptions.where(status: :active).where.not(
          SubscriptionBillingPeriod
            .covering(Time.current)
            .where("subscription_billing_periods.subscription_id = subscriptions.id")
            .arel.exists
        )
      end

      # A terminated subscription has nothing covering now — the writer clamps its final period to
      # `terminated_at` — so it needs a probe of its own, and the instant probed is one second before
      # the termination rather than the termination itself. A subscription terminated exactly when a
      # period opens collapses that period to nothing, and the writer legitimately stores no row for
      # it while leaving the preceding one ending on that very second.
      #
      # Bounded to the grace window, and to a subscription that lived past the probed second, both of
      # which the writer refuses to write for.
      def terminated_subscriptions_without_period
        probe = "subscriptions.terminated_at - interval '1 second'"

        UpsertService.recently_terminated(derivable_subscriptions)
          .where("subscriptions.started_at < #{probe}")
          .where.not(
            SubscriptionBillingPeriod
              .where("subscription_billing_periods.subscription_id = subscriptions.id")
              .where("subscription_billing_periods.period_from <= #{probe}")
              .where("subscription_billing_periods.period_to >= #{probe}")
              .arel.exists
          )
      end

      def report(count, what)
        return if count.zero?

        Rails.logger.warn(
          "[billing_periods] #{count} #{what} organization_id=#{organization.id}"
        )
      end
    end
  end
end
