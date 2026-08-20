# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Re-derives the periods of every subscription affected by a change to an input they share: the
    # applicable timezone of a customer or of a billing entity.
    #
    # The plan is not one of them: its interval and monthly-charges flag would move the boundaries,
    # but a plan attached to a subscription refuses both.
    #
    # A billing entity owns every customer of an organization by default, so the fan-out is
    # keyset-paged: one page of subscriptions per call, with the caller re-entering on the cursor,
    # rather than one call holding a connection for a walk over all of them.
    class RefreshAllService < BaseService
      Result = BaseResult[:enqueued_count, :next_cursor]

      BATCH_SIZE = 1_000

      def initialize(owner:, cursor: nil)
        @owner = owner
        @cursor = cursor

        super
      end

      def call
        # Resolved first so an unsupported owner is rejected whether the flag is on or off.
        scope = subscriptions

        result.enqueued_count = 0
        result.next_cursor = nil
        return result if organization.feature_flag_disabled?(:subscription_billing_periods)

        subscription_ids = scope
          .order("subscriptions.id")
          .limit(BATCH_SIZE)
          .pluck("subscriptions.id")
        return result if subscription_ids.empty?

        subscription_ids.each { |id| Subscriptions::BillingPeriods::UpsertJob.perform_later(id) }

        result.enqueued_count = subscription_ids.size
        # Only when the page is full: a shorter one is the last, and paging past it would cost a
        # query returning nothing.
        result.next_cursor = subscription_ids.last if subscription_ids.size == BATCH_SIZE
        result
      end

      private

      attr_reader :owner, :cursor

      def organization
        @organization ||= owner.organization
      end

      def subscriptions
        scope = case owner
        when Customer then Subscription.where(customer_id: owner.id)
        when BillingEntity then Subscription.joins(:customer).where(customers: {billing_entity_id: owner.id})
        else raise ArgumentError, "unsupported owner: #{owner.class}"
        end

        scope = scope.where("subscriptions.id > ?", cursor) if cursor

        scope.where(status: %i[active terminated])
      end
    end
  end
end
