# frozen_string_literal: true

module Invoices
  class NotifyJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PDFS"])
        :pdfs
      else
        :invoices
      end
    end

    def perform(invoice:, **context)
      InvoiceMailer.with(invoice:, **context).created.deliver_later
    end
  end
end
