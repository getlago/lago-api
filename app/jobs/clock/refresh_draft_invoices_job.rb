# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      enqueue_refresh_jobs(Invoice.ready_to_be_refreshed.with_active_subscriptions)
      enqueue_refresh_jobs(Invoice.ready_to_be_refreshed.joins(:billing_segments).distinct)
    end

    private

    def enqueue_refresh_jobs(scope)
      scope.find_each do |invoice|
        Invoices::RefreshDraftJob.perform_later(invoice:)
      end
    end
  end
end
