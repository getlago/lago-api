# frozen_string_literal: true

class CreateFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :features, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.datetime :deleted_at # INDEX?
      t.timestamps

      t.index [:organization_id, :code], unique: true, where: "deleted_at IS NULL"
    end

    create_table :privileges, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :feature, type: :uuid, null: false, foreign_key: true, index: true
      t.string :code, null: false
      t.string :name
      t.string :value_type, null: false, default: "string"
      t.datetime :deleted_at # INDEX?
      t.timestamps

      t.index [:feature_id, :code], unique: true, where: "deleted_at IS NULL"
    end

    create_table :feature_entitlements, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :feature, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: true, foreign_key: true, type: :uuid
      t.string :subscription_external_id, null: true, index: true
      t.datetime :deleted_at # INDEX?
      t.timestamps

      t.index [:plan_id, :feature_id], unique: true, where: "deleted_at IS NULL"
      t.index [:subscription_external_id, :feature_id], unique: true, where: "deleted_at IS NULL"
      t.check_constraint "(plan_id IS NOT NULL AND subscription_external_id IS NULL) OR (plan_id IS NULL AND subscription_external_id IS NOT NULL)", name: "exactly_one_parent"
    end

    create_table :feature_entitlement_values, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :privilege, null: false, foreign_key: true, type: :uuid
      t.references :feature_entitlement, null: false, foreign_key: true, type: :uuid
      t.string :value, null: false
      t.datetime :deleted_at # INDEX?
      t.timestamps

      t.index [:privilege_id, :feature_entitlement_id], where: "deleted_at IS NULL"
    end

    create_table :subscription_feature_removals, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :feature, null: false, foreign_key: true, type: :uuid
      t.string :subscription_external_id, null: false, index: true
      t.datetime :deleted_at # INDEX?
      t.timestamps

      t.index [:subscription_external_id, :feature_id], unique: true, where: "deleted_at IS NULL"
    end
  end
end
