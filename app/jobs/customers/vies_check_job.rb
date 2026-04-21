# frozen_string_literal: true

module Customers
  class ViesCheckJob < ApplicationJob
    RETRY_DELAYS = [5.minutes, 5.minutes, 10.minutes, 20.minutes, 40.minutes].freeze
    MAX_RETRY_DELAY = 1.hour

    queue_as :default

    def perform(customer)
      vies_check_result = Customers::ViesCheckService.call(customer:)

      if vies_check_result.success?
        Customers::ApplyTaxesService.call(
          customer: customer,
          tax_codes: [vies_check_result.tax_code]
        )

        # Finalize any invoices that were blocked by VIES
        enqueue_pending_invoice_finalization(customer)
      else
        schedule_retry(customer, vies_check_result)
      end
    end

    private

    def schedule_retry(customer, vies_check_result)
      return unless vies_check_result.pending_vies_check

      ViesCheckJob.set(wait: retry_delay(vies_check_result.pending_vies_check)).perform_later(customer)
    end

    def enqueue_pending_invoice_finalization(customer)
      customer.invoices
        .where(status: %i[pending open], tax_status: "pending")
        .find_each do |invoice|
          Invoices::FinalizePendingViesInvoiceJob.perform_later(invoice)
        end
    end

    def retry_delay(pending_vies_check)
      RETRY_DELAYS[pending_vies_check.attempts_count.to_i - 1] || MAX_RETRY_DELAY
    end
  end
end
