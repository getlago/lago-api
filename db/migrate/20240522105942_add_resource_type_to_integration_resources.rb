class AddResourceTypeToIntegrationResources < ActiveRecord::Migration[7.0]
  def change
    add_column :integration_resources, :resource_type, :integer, null: false, default: 0
  end
end
