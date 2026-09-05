# frozen_string_literal: true

class AddCatalogPlanToPricing < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A plan rate card belongs to a legacy plan or a catalog plan, so plan_id
    # is no longer mandatory; a check keeps the "exactly one plan" guarantee.
    # The composite unique index mirrors the legacy (plan_id, rate_card_id)
    # one and also serves catalog_plan_id FK lookups (leftmost), so the column
    # needs no standalone index.
    add_reference :plan_rate_cards, :catalog_plan, type: :uuid, null: true, index: false
    add_foreign_key :plan_rate_cards, :catalog_plans, validate: false
    change_column_null :plan_rate_cards, :plan_id, true
    add_index :plan_rate_cards, %i[catalog_plan_id rate_card_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id",
      algorithm: :concurrently
    add_check_constraint :plan_rate_cards,
      "num_nonnulls(plan_id, catalog_plan_id) = 1",
      name: "plan_rate_cards_check_exactly_one_plan",
      validate: false

    # A contract prices through a legacy plan, a catalog plan, or neither
    # (plan-less), never both.
    add_reference :contracts, :catalog_plan, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :contracts, :catalog_plans, validate: false
    add_check_constraint :contracts,
      "num_nonnulls(plan_id, catalog_plan_id) <= 1",
      name: "contracts_check_single_plan",
      validate: false
  end

  def down
    remove_check_constraint :contracts, name: "contracts_check_single_plan"
    remove_foreign_key :contracts, :catalog_plans
    remove_reference :contracts, :catalog_plan

    remove_check_constraint :plan_rate_cards, name: "plan_rate_cards_check_exactly_one_plan"
    remove_index :plan_rate_cards, name: "index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id"
    change_column_null :plan_rate_cards, :plan_id, false
    remove_foreign_key :plan_rate_cards, :catalog_plans
    remove_reference :plan_rate_cards, :catalog_plan
  end
end
