class CreateBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    create_table :billable_metrics, id: :uuid do |t|
      t.references :organization, index: true, null: false, foreign_key: true, type: :uuid

      t.string :name, null: false
      t.string :code, null: false
      t.string :description
      t.integer :billable_period, null: false
      t.boolean :pro_rata, default: false, null: false
      t.jsonb :properties, default: {}
      t.integer :aggregation_type, null: false

      t.timestamps

      t.index %i[organization_id code], unique: true
    end
  end
end
