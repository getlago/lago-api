# frozen_string_literal: true

class AddBillingEntityToQuoteVersions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_reference :quote_versions, :billing_entity, type: :uuid, null: true, index: {algorithm: :concurrently}
    add_foreign_key :quote_versions, :billing_entities, validate: false
  end
end
