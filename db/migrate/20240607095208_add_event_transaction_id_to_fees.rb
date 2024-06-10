# frozen_string_literal: true

class AddEventTransactionIdToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :pay_in_advance_event_transaction_id, :string
  end
end
