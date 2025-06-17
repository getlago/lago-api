# frozen_string_literal: true

class AddIndexOnPaymentRequestsPayableIdAndPayableType < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :payment_requests,
      [:payment_requestable_type, :payment_requestable_id],
      algorithm: :concurrently,
      if_not_exists: true

    add_index :payments,
      :payment_request_id,
      algorithm: :concurrently,
      if_not_exists: true
  end
end
