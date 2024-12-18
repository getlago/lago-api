# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      Invoice.ready_to_be_refreshed.with_active_subscriptions.find_each do |invoice|
        Invoices::RefreshDraftJob.perform_later(invoice)
      end
    end
  end
end
