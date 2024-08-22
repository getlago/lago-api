class AddPaymentRetryColumnsToPaymentRequests < ActiveRecord::Migration[7.1]
  def change
    change_table :payment_requests, bulk: true do |t|
      t.integer :payment_attempts, default: 0, null: false
      t.boolean :ready_for_payment_processing, default: true, null: false
    end
  end
end
