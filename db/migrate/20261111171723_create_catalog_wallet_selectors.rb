# frozen_string_literal: true

class CreateCatalogWalletSelectors < ActiveRecord::Migration[8.1]
  def change
    create_enum :catalog_wallet_selector_type, %w[fee_type product_category product product_filters]
    create_enum :catalog_wallet_selector_fee_type, %w[fixed metered]

    create_table :catalog_wallet_selectors, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :plan_wallet, type: :uuid, foreign_key: true, index: false
      t.references :catalog_wallet, type: :uuid, foreign_key: true, index: false
      t.references :product_category, type: :uuid, foreign_key: true, index: false
      t.references :product, type: :uuid, foreign_key: true, index: false
      t.references :product_filter, type: :uuid, foreign_key: true, index: false

      t.enum :selector_type, enum_type: :catalog_wallet_selector_type, null: false
      t.enum :fee_type, enum_type: :catalog_wallet_selector_fee_type
      t.boolean :with_product_filters, null: false, default: false

      t.timestamps

      t.index %i[plan_wallet_id selector_type fee_type product_category_id product_id product_filter_id],
        unique: true,
        nulls_not_distinct: true,
        where: "plan_wallet_id IS NOT NULL",
        name: "index_catalog_wallet_selectors_on_plan_wallet_and_target"
      t.index %i[catalog_wallet_id selector_type fee_type product_category_id product_id product_filter_id],
        unique: true,
        nulls_not_distinct: true,
        where: "catalog_wallet_id IS NOT NULL",
        name: "index_catalog_wallet_selectors_on_catalog_wallet_and_target"

      t.check_constraint "num_nonnulls(plan_wallet_id, catalog_wallet_id) = 1",
        name: "catalog_wallet_selectors_exactly_one_owner"
      t.check_constraint <<~SQL.squish, name: "catalog_wallet_selectors_target_matches_type"
        num_nonnulls(fee_type, product_category_id, product_id, product_filter_id) = 1
        AND CASE selector_type
          WHEN 'fee_type' THEN fee_type IS NOT NULL
          WHEN 'product_category' THEN product_category_id IS NOT NULL
          WHEN 'product' THEN product_id IS NOT NULL
          WHEN 'product_filters' THEN product_filter_id IS NOT NULL
        END
        AND (selector_type = 'product' OR NOT with_product_filters)
      SQL
    end
  end
end
