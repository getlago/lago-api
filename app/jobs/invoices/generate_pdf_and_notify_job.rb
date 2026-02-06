# frozen_string_literal: true

module Invoices
  class GeneratePdfAndNotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :invoices
      end
    end

    def perform(invoice:, email:, **context)
      Invoices::GenerateDocumentsJob.perform_later(invoice:, notify: email, **context)
    end
  end
end
