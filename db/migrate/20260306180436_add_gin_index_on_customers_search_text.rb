# frozen_string_literal: true

class AddGinIndexOnCustomersSearchText < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      enable_extension "pg_trgm"
      enable_extension "btree_gin"
    end

    add_index :customers, [:organization_id, :search_text],
      using: :gin,
      opclass: {search_text: :gin_trgm_ops},
      name: :index_customers_on_organization_id_and_search_text,
      algorithm: :concurrently
  end

  def down
    remove_index :customers,
      name: :index_customers_on_organization_id_and_search_text,
      algorithm: :concurrently

    safety_assured do
      disable_extension "btree_gin"
      disable_extension "pg_trgm"
    end
  end
end
