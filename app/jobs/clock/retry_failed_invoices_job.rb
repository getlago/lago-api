# frozen_string_literal: true

module Clock
  class RetryFailedInvoicesJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    def perform
      Invoice
        .failed
        .joins(:error_details)
        .where("error_details.details ? 'tax_error_message'")
        .where("error_details.details ->> 'tax_error_message' ILIKE ?", "%API limit%").find_each do |i|
        Invoices::RetryService.call(invoice: i)
      end
    end
  end
end
