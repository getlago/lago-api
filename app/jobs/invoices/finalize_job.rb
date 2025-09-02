# frozen_string_literal: true

module Invoices
  class FinalizeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :invoices
      end
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

    def perform(invoice)
      Invoices::RefreshDraftAndFinalizeService.call(invoice:)
    end
  end
end
