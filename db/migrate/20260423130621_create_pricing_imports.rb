# frozen_string_literal: true

class CreatePricingImports < ActiveRecord::Migration[8.0]
  def change
    create_enum :pricing_import_state, %w[draft confirmed processing completed failed]

    create_table :pricing_imports, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :membership, null: true, foreign_key: true, type: :uuid

      t.enum :state, enum_type: :pricing_import_state, null: false, default: "draft"

      t.string :source_filename
      t.jsonb :proposed_plan, default: {}, null: false
      t.jsonb :edited_plan, default: {}, null: false
      t.jsonb :execution_report, default: [], null: false

      t.integer :progress_current, default: 0, null: false
      t.integer :progress_total, default: 0, null: false

      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
  end
end
