# frozen_string_literal: true

class AddCatalogPlanToPricingTables < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # plan_rate_cards and contracts only ever pointed at product-catalog plans,
    # which now live in catalog_plans. Repoint them there. The old plan_id stays
    # as a dead nullable column, dropped in a follow-up once no row uses it.

    # The composite unique index mirrors the legacy (plan_id, rate_card_id) one
    # and serves catalog_plan_id FK lookups (leftmost), so no standalone index.
    add_reference :plan_rate_cards, :catalog_plan, type: :uuid, null: true, index: false
    add_foreign_key :plan_rate_cards, :catalog_plans, validate: false
    add_index :plan_rate_cards, %i[catalog_plan_id rate_card_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id",
      algorithm: :concurrently
    # New rows carry catalog_plan_id, not plan_id.
    change_column_null :plan_rate_cards, :plan_id, true

    add_reference :contracts, :catalog_plan, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :contracts, :catalog_plans, validate: false
  end

  def down
    remove_foreign_key :contracts, :catalog_plans
    remove_reference :contracts, :catalog_plan

    change_column_null :plan_rate_cards, :plan_id, false
    remove_index :plan_rate_cards, name: "index_plan_rate_cards_on_catalog_plan_id_and_rate_card_id"
    remove_foreign_key :plan_rate_cards, :catalog_plans
    remove_reference :plan_rate_cards, :catalog_plan
  end
end
