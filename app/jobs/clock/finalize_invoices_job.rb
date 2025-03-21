# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
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

    unique :until_executed, on_conflict: :log

    def perform
      Invoice.ready_to_be_finalized.find_each do |invoice|
        Invoices::FinalizeJob.perform_later(invoice)
      end
    end
  end
end
