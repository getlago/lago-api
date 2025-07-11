# frozen_string_literal: true

module DatabaseMigrations
  class PopulatePaymentsWithCustomerId < ApplicationJob
    queue_as :low_priority
    unique :until_executed

    BATCH_SIZE = 1000

    def perform(batch_number = 1)
      # rubocop:disable Rails/SkipsModelValidations
      Payment.where(payable_type: "Invoice", customer_id: nil)
        .limit(BATCH_SIZE)
        .update_all("customer_id = (SELECT customer_id FROM invoices WHERE invoices.id = payments.payable_id)")

      Payment.where(payable_type: "PaymentRequest", customer_id: nil)
        .limit(BATCH_SIZE)
        .update_all("customer_id = (SELECT customer_id FROM payment_requests WHERE payment_requests.id = payments.payable_id)")
      # rubocop:enable Rails/SkipsModelValidations

      # Queue the next batch
      self.class.perform_later(batch_number + 1) if Payment.where(customer_id: nil).exists?
    end

    def lock_key_arguments
      [arguments]
    end
  end
end
