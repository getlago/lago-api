class AddIndexOnCustomersExternalId < ActiveRecord::Migration[7.0]
  def change
    add_index :customers, :external_id
  end
end
