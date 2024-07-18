class CreateIntegrationErrorDetails < ActiveRecord::Migration[7.1]
  def change
    create_table :integration_error_details, id: :uuid do |t|
      t.references :owner, type: :uuid, polymorphic: true, null: false, index: true
      t.references :integration, type: :uuid, index: true, foreign_key: true, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :deleted_at, index: true
    end
  end
end
