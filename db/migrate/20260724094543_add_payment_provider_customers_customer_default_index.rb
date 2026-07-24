# frozen_string_literal: true

class AddPaymentProviderCustomersCustomerDefaultIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One default payment connection per customer (active rows only).
    add_index :payment_provider_customers, :customer_id,
      unique: true,
      where: "is_default AND deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_payment_provider_customers_on_customer_id_default"
  end
end
