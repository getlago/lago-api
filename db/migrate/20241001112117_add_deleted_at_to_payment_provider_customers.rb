# frozen_string_literal: true

class AddDeletedAtToPaymentProviderCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    safety_assured do
      add_column :payment_provider_customers, :deleted_at, :datetime

      remove_index :payment_provider_customers, %i[customer_id type]
      add_index :payment_provider_customers, %i[customer_id type], unique: true, where: 'deleted_at IS NULL'
    end
  end

  def down
    safety_assured do
      remove_column :payment_provider_customers, :deleted_at
      add_index :payment_provider_customers, %i[customer_id type], unique: true
    end
  end
end
