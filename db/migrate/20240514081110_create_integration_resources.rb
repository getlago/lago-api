class CreateIntegrationResources < ActiveRecord::Migration[7.0]
  def change
    create_table :integration_resources, id: :uuid do |t|
      t.references :syncable, polymorphic: true, index: true, null: false, type: :uuid
      t.string :external_id

      t.timestamps
    end
  end
end
