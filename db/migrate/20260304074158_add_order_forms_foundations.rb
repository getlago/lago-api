# frozen_string_literal: true

class AddOrderFormsFoundations < ActiveRecord::Migration[8.0]
  def change
    create_enum :quote_status, %w[draft approved voided]

    create_table :quotes, id: :uuid do |t|
      # identity
      t.references :organization,
        null: false,
        foreign_key: true,
        index: false, # covered by the composite unique index below
        type: :uuid
      t.references :customer,
        null: false,
        foreign_key: true,
        type: :uuid
      t.string :number, null: false
      t.integer :version, null: false, default: 1
      t.integer :sequential_id, null: false
      t.integer :order_type, null: false, comment: "Rails enum"
      t.string :currency
      t.text :description
      # lifecycle
      t.enum :status,
        enum_type: :quote_status,
        null: false,
        default: "draft"
      t.datetime :approved_at
      t.datetime :voided_at
      t.integer :void_reason, comment: "Rails enum"
      t.timestamps
      # content
      t.jsonb :billing_items
      t.jsonb :commercial_terms
      t.text :content
      t.text :legal_text
      t.text :internal_notes
      t.jsonb :contacts
      t.jsonb :metadata
      t.boolean :auto_execute, null: false, default: false
      t.integer :backdated_billing, comment: "Rails enum"
      t.integer :execution_mode, comment: "Rails enum"
      t.string :share_token

      # constraints and indices
      t.check_constraint "version > 0",
        name: "quotes_constraint_version_positive"
      t.check_constraint "sequential_id > 0",
        name: "quotes_constraint_sequentialid_positive"
      t.index [:organization_id, :sequential_id, :version],
        unique: true,
        order: {version: :desc},
        name: "index_unique_quotes_on_organization_sequentialid_version"
      t.index [:organization_id, :number],
        unique: true,
        name: "index_unique_quotes_on_organization_number"
      t.index :share_token,
        unique: true,
        name: "index_unique_quotes_on_share_token"
    end

    create_enum :order_form_status, %w[generated signed expired voided]

    create_table :order_forms, id: :uuid do |t|
      # identity
      t.references :organization,
        null: false,
        foreign_key: true,
        index: false, # covered by the composite unique index below
        type: :uuid
      t.references :customer,
        null: false,
        foreign_key: true,
        type: :uuid
      t.references :quote,
        null: false,
        foreign_key: true,
        type: :uuid
      t.string :number, null: false
      t.integer :sequential_id, null: false
      # lifecycle
      t.enum :status,
        enum_type: :order_form_status,
        null: false,
        default: "generated"
      t.integer :void_reason, comment: "Rails enum"
      t.references :signed_by_user,
        foreign_key: {to_table: :users},
        index: false,
        null: true,
        type: :uuid
      t.uuid :contract_uploaded_by_user
      t.datetime :contract_uploaded_at
      t.datetime :expires_at
      t.datetime :signed_at
      t.datetime :voided_at
      t.timestamps
      # content
      t.jsonb :billing_snapshot, null: false
      t.text :content
      t.text :legal_text

      # constraints and indices
      t.check_constraint "sequential_id > 0",
        name: "order_forms_constraint_sequentialid_positive"
      t.index [:organization_id, :sequential_id],
        unique: true,
        name: "index_unique_order_forms_on_organization_sequentialid"
      t.index [:organization_id, :number],
        unique: true,
        name: "index_unique_order_forms_on_organization_number"
    end

    create_enum :order_status, %w[created executed]

    create_table :orders, id: :uuid do |t|
      # identity
      t.references :organization,
        null: false,
        foreign_key: true,
        index: false, # covered by the composite unique index below
        type: :uuid
      t.references :customer,
        null: false,
        foreign_key: true,
        type: :uuid
      t.references :order_form,
        null: false,
        foreign_key: true,
        type: :uuid
      t.string :number, null: false
      t.integer :sequential_id, null: false
      t.integer :order_type, null: false, comment: "Rails enum"
      # lifecycle
      t.enum :status,
        enum_type: :order_status,
        null: false,
        default: "created"
      t.datetime :executed_at
      t.timestamps
      # content
      t.string :currency
      t.jsonb :billing_snapshot, null: false
      t.integer :execution_mode, comment: "Rails enum"
      t.integer :backdated_billing, comment: "Rails enum"
      t.json :execution_record

      # constraints and indices
      t.check_constraint "sequential_id > 0",
        name: "orders_constraint_sequentialid_positive"
      t.index [:organization_id, :sequential_id],
        unique: true,
        name: "index_unique_orders_on_organization_sequentialid"
      t.index [:organization_id, :number],
        unique: true,
        name: "index_unique_orders_on_organization_number"
    end

    create_table :quote_owners do |t|
      t.references :organization,
        null: false,
        foreign_key: true,
        type: :uuid
      t.references :quote,
        null: false,
        foreign_key: true,
        index: false, # covered by the composite unique index below
        type: :uuid
      t.references :user,
        null: false,
        foreign_key: true,
        type: :uuid
      t.timestamps

      t.index [:quote_id, :user_id],
        unique: true,
        name: "index_unique_quote_owners_on_quote_and_user"
    end
  end
end
