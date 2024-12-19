class AddTypeColumnToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :type, :string, default: "Customer", null: false
  end
end
