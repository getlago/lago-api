# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
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
