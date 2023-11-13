class AddCodeToPaymentProviders < ActiveRecord::Migration[7.0]
  def change
    add_column :payment_providers, :name, :string
    add_column :payment_providers, :code, :string, null: false

    add_index :payment_providers, [:organization_id, :code], unique: true

    LagoApi::Application.load_tasks
    Rake::Task['payment_providers:generate_code'].invoke
  end
end
