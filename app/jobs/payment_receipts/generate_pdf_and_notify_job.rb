# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaymentReceipts
  class GeneratePdfAndNotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :low_priority
      end
    end

    def perform(payment_receipt:, email:)
      PaymentReceipts::GenerateDocumentsJob.perform_later(payment_receipt:, notify: email)
    end
  end
end
