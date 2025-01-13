class AddAccountTypeToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :account_type, :string, null: true

    Account.update_all(account_type: "Customer") # rubocop:disable Rails/SkipsModelValidations
  end
end
