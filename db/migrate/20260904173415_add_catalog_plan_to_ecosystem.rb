# frozen_string_literal: true

class AddCatalogPlanToEcosystem < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_reference :coupon_targets, :catalog_plan, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :coupon_targets, :catalog_plans, validate: false

    # A tax now attaches to a legacy plan or a catalog plan, so plan_id is no
    # longer mandatory. The composite unique index mirrors the legacy
    # (plan_id, tax_id) one and also serves catalog_plan_id FK lookups
    # (leftmost), so the column needs no standalone index.
    add_reference :plans_taxes, :catalog_plan, type: :uuid, null: true, index: false
    add_foreign_key :plans_taxes, :catalog_plans, validate: false
    change_column_null :plans_taxes, :plan_id, true
    add_index :plans_taxes, %i[catalog_plan_id tax_id], unique: true, algorithm: :concurrently

    add_reference :entitlement_entitlements, :catalog_plan, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :entitlement_entitlements, :catalog_plans, validate: false
    add_index :entitlement_entitlements, %i[entitlement_feature_id catalog_plan_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: "idx_unique_feature_per_catalog_plan",
      algorithm: :concurrently

    # The catalog plan joins plan and subscription as a valid parent, so the
    # exactly-one-parent check must count all three, not just plan XOR
    # subscription. Existing rows already satisfy it, so it validates in the
    # follow-up migration.
    remove_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
    add_check_constraint :entitlement_entitlements,
      "num_nonnulls(plan_id, catalog_plan_id, subscription_id) = 1",
      name: "entitlement_check_exactly_one_parent",
      validate: false
  end

  def down
    remove_check_constraint :entitlement_entitlements, name: "entitlement_check_exactly_one_parent"
    add_check_constraint :entitlement_entitlements,
      "(plan_id IS NOT NULL) <> (subscription_id IS NOT NULL)",
      name: "entitlement_check_exactly_one_parent"

    remove_index :entitlement_entitlements, name: "idx_unique_feature_per_catalog_plan"
    remove_foreign_key :entitlement_entitlements, :catalog_plans
    remove_reference :entitlement_entitlements, :catalog_plan

    remove_index :plans_taxes, name: "index_plans_taxes_on_catalog_plan_id_and_tax_id"
    change_column_null :plans_taxes, :plan_id, false
    remove_foreign_key :plans_taxes, :catalog_plans
    remove_reference :plans_taxes, :catalog_plan

    remove_foreign_key :coupon_targets, :catalog_plans
    remove_reference :coupon_targets, :catalog_plan
  end
end
