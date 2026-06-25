# frozen_string_literal: true

module Clock
  # Drains the outbox: groups the pending billing cycles by (subscription, billing_at)
  # and fans out a ProcessJob per group, so every cycle a subscription owes on a given
  # boundary lands on a single invoice. The heavy work (fees, taxes, finalization) lives
  # in the per-group job, keeping the scan cheap. This is the second lane, decoupled
  # from cycle creation so a slow or failing invoice never holds up the clock.
  class ProcessBillingCyclesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      BillingCycle
        .pending
        .distinct
        .pluck(:subscription_id, :billing_at)
        .each do |subscription_id, billing_at|
          BillingCycles::ProcessJob.perform_later(Subscription.find(subscription_id), billing_at)
        end
    end
  end
end
