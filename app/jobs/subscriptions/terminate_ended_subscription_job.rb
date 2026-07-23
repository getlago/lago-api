# frozen_string_literal: true

module Subscriptions
  # Handles async termination of ended subscriptions from `Clock::TerminateEndedSubscriptionsJob`.
  # Intentionally on the `default` queue: this job only triggers termination which schedules
  # billing separately — it doesn't perform billing itself, so it shouldn't compete
  # with billing jobs on the :billing queue.
  class TerminateEndedSubscriptionJob < ApplicationJob
    unique :until_executed, on_conflict: :log

    def perform(subscription)
      # NOTE: Pin termination to the subscription's contractual end so billing stops exactly
      #       at `ending_at`, regardless of when this (hourly) job actually runs. The
      #       termination-side dedup in Invoices::CreateInvoiceSubscriptionService prevents a
      #       period already billed periodically from being billed again.
      Subscriptions::TerminateService.call!(subscription:, terminated_at: subscription.ending_at)
    end
  end
end
