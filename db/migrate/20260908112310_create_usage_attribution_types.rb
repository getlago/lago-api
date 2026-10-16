# frozen_string_literal: true

class CreateUsageAttributionTypes < ActiveRecord::Migration[8.0]
  def change
    create_enum :usage_attribution_type_role, %w[hierarchical flat]

    create_table :usage_attribution_types, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :parent, type: :uuid, null: true, foreign_key: {to_table: :usage_attribution_types}, index: true

      t.string :code, null: false
      t.string :name
      t.string :attribution_key, null: false
      t.enum :role, enum_type: :usage_attribution_type_role, null: false

      t.datetime :deleted_at

      t.timestamps

      t.index %i[organization_id code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_usage_attribution_types_on_organization_id_and_code"
      t.index %i[organization_id attribution_key],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_usage_attribution_types_on_organization_id_and_key"
    end
  end
end
