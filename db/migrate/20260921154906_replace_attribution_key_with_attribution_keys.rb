# frozen_string_literal: true

class ReplaceAttributionKeyWithAttributionKeys < ActiveRecord::Migration[8.0]
  def up
    add_column :usage_attribution_types, :attribution_keys, :string, array: true, default: [], null: false

    safety_assured do
      remove_index :usage_attribution_types, name: "index_usage_attribution_types_on_organization_id_and_key"
      remove_column :usage_attribution_types, :attribution_key
    end
  end

  def down
    safety_assured do
      remove_column :usage_attribution_types, :attribution_keys
      add_column :usage_attribution_types, :attribution_key, :string, null: false, default: ""
      change_column_default :usage_attribution_types, :attribution_key, from: "", to: nil
    end

    add_index :usage_attribution_types,
      %i[organization_id attribution_key],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_usage_attribution_types_on_organization_id_and_key"
  end
end
