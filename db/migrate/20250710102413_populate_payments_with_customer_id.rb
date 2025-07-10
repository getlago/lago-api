# frozen_string_literal: true

class PopulatePaymentsWithCustomerId < ActiveRecord::Migration[8.0]
  def change
    # rubocop:disable Rails/SkipsModelValidations
    Payment.where(payable_type: "Invoice")
      .find_in_batches(batch_size: 1000) do |batch|
      Payment.where(id: batch.pluck(:id))
        .update_all("customer_id = (SELECT customer_id FROM invoices WHERE invoices.id = payments.payable_id)")
    end

    Payment.where(payable_type: "PaymentRequest")
      .find_in_batches(batch_size: 1000) do |batch|
      Payment.where(id: batch.pluck(:id))
        .update_all("customer_id = (SELECT customer_id FROM payment_requests WHERE payment_requests.id = payments.payable_id)")
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
