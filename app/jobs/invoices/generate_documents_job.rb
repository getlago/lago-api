# frozen_string_literal: true

module Invoices
  class GenerateDocumentsJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :invoices
      end
    end

    retry_on LagoHttpClient::HttpError, Errno::ECONNREFUSED, EOFError, wait: :polynomially_longer, attempts: 6

    def perform(invoice:, notify: false)
      result = Invoices::GenerateXmlService.call(invoice:)
      result.raise_if_error!

      result = Invoices::GeneratePdfService.call(invoice:)
      result.raise_if_error!

      Invoices::NotifyJob.perform_later(invoice:) if notify
    end
  end
end
