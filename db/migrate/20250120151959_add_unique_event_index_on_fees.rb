# frozen_string_literal: true

class AddUniqueEventIndexOnFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees, %i[pay_in_advance_event_transaction_id charge_id charge_filter_id], unique: true,
      where: "created_at > '#{Time.current}'", algorithm: :concurrently
  end
end
