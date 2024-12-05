# frozen_string_literal: true

module Invoices
  class FinalizeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_BILLING'])
        :billing
      else
        :invoices
      end
    end

    unique :until_executed, on_conflict: :log

    retry_on Sequenced::SequenceError, wait: :polynomially_longer

    def perform(invoice)
      Invoices::RefreshDraftAndFinalizeService.call(invoice:)
    end
  end
end
