# frozen_string_literal: true

class AddAbandonedAuthenticationIndexToPayments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :payments,
      :updated_at,
      where: "status = 'requires_action' AND payable_payment_status = 'processing'",
      name: "index_payments_on_updated_at_awaiting_authentication",
      algorithm: :concurrently
  end
end
