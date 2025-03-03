# frozen_string_literal: true

module PaymentReceipts
  class GeneratePdfAndNotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :low_priority
      end
    end

    retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 6

    def perform(payment_receipt:, email:)
      PaymentReceipts::GeneratePdfService.call!(payment_receipt:, context: "api")

      if email
        PaymentReceiptMailer.with(payment_receipt:).created.deliver_later
      end
    end
  end
end
