# frozen_string_literal: true

class AddPayablePaymentStatusToPayment < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_enum :payment_payable_payment_status,
      %w[
        pending
        processing
        succeeded
        failed
      ]

    add_column :payments,
      :payable_payment_status,
      :enum,
      enum_type: "payment_payable_payment_status",
      null: true

    add_index :payments,
      %i[payable_id payable_type],
      where: "payable_payment_status in ('pending', 'processing')",
      unique: true,
      algorithm: :concurrently
  end
end
