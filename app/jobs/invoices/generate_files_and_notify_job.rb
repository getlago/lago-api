# frozen_string_literal: true

module Invoices
  class GenerateFilesAndNotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :invoices
      end
    end

    retry_on LagoHttpClient::HttpError, Errno::ECONNREFUSED, wait: :polynomially_longer, attempts: 6

    def perform(invoice:, email:)
      result = Invoices::GenerateXmlService.call(invoice:)
      result.raise_if_error!

      result = Invoices::GeneratePdfService.call(invoice:)
      result.raise_if_error!

      if email
        InvoiceMailer.with(invoice:).finalized.deliver_later
      end
    end
  end
end
