# frozen_string_literal: true

class AddDeletedAtToPaymentProviderCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :payment_provider_customers, :deleted_at, :datetime
    remove_index :payment_provider_customers, %i[customer_id type]
    add_index :payment_provider_customers, %i[customer_id type], unique: true, where: 'deleted_at IS NULL', algorithm: :concurrently
  end

  def down
    remove_column :payment_provider_customers, :deleted_at
    add_index :payment_provider_customers, %i[customer_id type], unique: true, algorithm: :concurrently
  end
end
