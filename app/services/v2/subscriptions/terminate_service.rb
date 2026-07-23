# frozen_string_literal: true

module V2
  module Subscriptions
    # Terminates a subscription in the new engine: ends every still-active product item
    # and lets each emit its final prorated cycle. Per-item (each item resolves its own
    # rate/period for the closing cycle), so it loops the per-item TerminateService.
    # Separate from the legacy Subscriptions::TerminateService — the two engines run
    # side by side until the migration completes. Advance items credit their unused
    # remainder instead of a final cycle, so the emitted credit notes are surfaced too.
    class TerminateService < BaseService
      Result = BaseResult[:subscription, :subscription_rate_cards, :credit_notes]

      def initialize(subscription:, terminated_at: Time.current)
        @subscription = subscription
        @terminated_at = terminated_at
        super
      end

      def call
        ActiveRecord::Base.transaction do
          result.subscription_rate_cards = subscription.subscription_rate_cards.where(ended_at: nil).map do |item|
            SubscriptionRateCards::TerminateService
              .call!(subscription_rate_card: item, terminated_at:)
              .subscription_rate_card
          end

          # Credit the unused advance remainder once all items are ended, grouped by
          # invoice so items billed together produce a single credit note.
          result.credit_notes = CreditUnusedAdvanceService
            .call(subscription:, terminated_at:)
            .credit_notes

          subscription.mark_as_terminated!(terminated_at)
        end

        # Bill the final (arrears) cycle right away instead of waiting for the periodic
        # clock — the final invoice should land on termination, matching the legacy engine.
        after_commit { BillingCycles::BillSubscriptionJob.perform_later(subscription) }

        result.subscription = subscription
        result
      end

      private

      attr_reader :subscription, :terminated_at
    end
  end
end
