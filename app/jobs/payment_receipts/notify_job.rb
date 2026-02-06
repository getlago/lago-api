# frozen_string_literal: true

module PaymentReceipts
  class NotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :low_priority
      end
    end

    def perform(payment_receipt:, **context)
      PaymentReceiptMailer.with(payment_receipt:, **context).created.deliver_later
    end
  end
end
