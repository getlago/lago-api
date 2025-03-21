# frozen_string_literal: true

module Clock
  class MarkInvoicesAsPaymentOverdueJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      Invoice
        .finalized
        .not_payment_succeeded
        .where(payment_overdue: false)
        .where(payment_dispute_lost_at: nil)
        .where(payment_due_date: ...Time.current)
        .find_each do |invoice|
          invoice.update!(payment_overdue: true)
          SendWebhookJob.perform_later("invoice.payment_overdue", invoice)
        end
    end
  end
end
