# frozen_string_literal: true

module Invoices
  class GeneratePdfAndNotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_PDFS'])
        :pdfs
      else
        :default
      end
    end

    def perform(invoice:, email:)
      result = Invoices::GeneratePdfService.call(invoice:)
      result.raise_if_error!

      if email
        InvoiceMailer.with(invoice:).finalized.deliver_later
      end
    end
  end
end
