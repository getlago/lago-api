# frozen_string_literal: true

class AddPaymentProviderCustomersCustomerCodeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One code per customer on payment_provider_customers (active rows only).
    add_index :payment_provider_customers, %i[customer_id code],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_payment_provider_customers_on_customer_id_and_code"
  end
end
