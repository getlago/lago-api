# frozen_string_literal: true

module Invoices
  class FinalizePendingViesInvoiceJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    def perform(invoice)
      Invoices::FinalizePendingViesInvoiceService.call!(invoice:)
    end
  end
end
