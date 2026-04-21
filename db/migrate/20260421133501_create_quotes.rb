# frozen_string_literal: true

class CreateQuotes < ActiveRecord::Migration[8.0]
  def change
    create_enum :quote_status, %w[draft approved voided]
    create_enum :quote_order_type, %w[subscription_creation subscription_amendment one_off]
    create_enum :quote_void_reason, %w[manual superseded cascade_of_expired cascade_of_voided]

    create_table :quotes, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, index: false, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.string :number, null: false
      t.integer :version, null: false, default: 1
      t.integer :sequential_id, null: false
      t.enum :order_type, enum_type: :quote_order_type, null: false
      t.string :currency
      t.text :description
      t.enum :status, enum_type: :quote_status, null: false, default: "draft"
      t.datetime :approved_at
      t.datetime :voided_at
      t.enum :void_reason, enum_type: :quote_void_reason
      t.timestamps
      t.jsonb :billing_items
      t.jsonb :commercial_terms
      t.text :content
      t.text :legal_text
      t.text :internal_notes
      t.jsonb :contacts
      t.jsonb :metadata
      t.string :share_token

      t.check_constraint "version > 0", name: "quotes_constraint_version_positive"
      t.check_constraint "sequential_id > 0", name: "quotes_constraint_sequentialid_positive"
      t.index [:organization_id, :sequential_id, :version],
        unique: true,
        order: {version: :desc},
        name: "index_unique_quotes_on_organization_sequentialid_version"
      t.index [:organization_id, :number], name: "index_quotes_on_organization_number"
      t.index :share_token, unique: true, name: "index_unique_quotes_on_share_token"
    end
  end
end
