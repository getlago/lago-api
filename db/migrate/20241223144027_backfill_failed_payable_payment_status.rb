# frozen_string_literal: true

class BackfillFailedPayablePaymentStatus < ActiveRecord::Migration[7.1]
  def change
    Payment.where(status: "failed", payable_payment_status: nil)
      .update_all(payable_payment_status: "failed") # rubocop:disable Rails/SkipsModelValidations
  end
end
