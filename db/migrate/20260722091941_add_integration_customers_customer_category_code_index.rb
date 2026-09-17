# frozen_string_literal: true

class AddIntegrationCustomersCustomerCategoryCodeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # One code per (customer, category) on integration_customers.
    add_index :integration_customers, %i[customer_id category code],
      unique: true,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_integration_customers_on_customer_category_code"
  end
end
