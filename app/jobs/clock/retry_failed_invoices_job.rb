# frozen_string_literal: true

module Clock
  class RetryFailedInvoicesJob < ClockJob
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
