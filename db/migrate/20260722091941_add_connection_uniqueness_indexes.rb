# frozen_string_literal: true

class AddConnectionUniquenessIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One code per (customer, category) on integration_customers.
    add_index :integration_customers, %i[customer_id category code],
      unique: true,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_integration_customers_on_customer_category_code"

    # One default connection per (customer, category) on integration_customers.
    add_index :integration_customers, %i[customer_id category],
      unique: true,
      where: "is_default",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_integration_customers_on_customer_category_default"

    # One code per customer on payment_provider_customers (active rows only).
    add_index :payment_provider_customers, %i[customer_id code],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_payment_provider_customers_on_customer_id_and_code"

    # One default payment connection per customer (active rows only).
    add_index :payment_provider_customers, :customer_id,
      unique: true,
      where: "is_default AND deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_payment_provider_customers_on_customer_id_default"
  end
end
