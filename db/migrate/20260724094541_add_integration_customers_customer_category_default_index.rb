# frozen_string_literal: true

class AddIntegrationCustomersCustomerCategoryDefaultIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One default connection per (customer, category) on integration_customers.
    add_index :integration_customers, %i[customer_id category],
      unique: true,
      where: "is_default",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_integration_customers_on_customer_category_default"
  end
end
