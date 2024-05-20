class AddIntegrationIdToIntegrationResources < ActiveRecord::Migration[7.0]
  def up
    remove_index :integration_items, [:external_id, :integration_id]

    add_index :integration_items,
      [:external_id, :integration_id, :item_type],
      name: :index_int_items_on_external_id_and_int_id_and_type,
      unique: true

    add_reference :integration_resources, :integration, type: :uuid, foreign_key: true
  end

  def down
    remove_index :integration_items, [:external_id, :integration_id, :item_type]

    add_index :integration_items, [:external_id, :integration_id], unique: true

    remove_reference :integration_resources, :integration
  end
end
