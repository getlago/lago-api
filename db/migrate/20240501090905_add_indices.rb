# frozen_string_literal: true

class AddIndices < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :subscriptions, :ending_at
    add_index :subscriptions, :billing_time
    add_index :plans, :interval
    add_index :fees, :fee_type
    add_index :fees, :payment_status
    add_index :charges, :charge_model
  end
end
