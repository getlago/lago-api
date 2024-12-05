# frozen_string_literal: true

class BillNonInvoiceableFeesJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_BILLING'])
      :billing
    else
      :default
    end
  end

  retry_on Sequenced::SequenceError, ActiveJob::DeserializationError

  def perform(subscriptions, billing_at)
    result = Invoices::AdvanceChargesService.call(subscriptions:, billing_at:)
    result.raise_if_error!
  end
end
