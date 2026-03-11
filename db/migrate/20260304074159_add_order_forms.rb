# frozen_string_literal: true

class AddOrderForms < ActiveRecord::Migration[8.0]
  def change
    create_enum :order_form_status, %w[draft published signed executed voided]
    create_enum :order_form_void_reason, %w[manual expired superseded invalid]

    create_table :order_forms, id: :uuid do |t|
      # identity
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.string :number, null: false
      t.integer :version, null: false, default: 1
      t.integer :sequential_id, null: false
      # lifecycle
      t.enum :status, enum_type: :order_form_status, null: false, default: "draft"
      t.enum :void_reason, enum_type: :order_form_void_reason
      t.uuid :signed_by_user_id
      t.string :share_token
      t.jsonb :validation_errors
      t.datetime :validated_at
      t.datetime :published_at
      t.datetime :signed_at
      t.datetime :executed_at
      t.datetime :expires_at
      t.datetime :voided_at
      # content
      t.jsonb :billing_payload, null: false, default: {}
      t.boolean :auto_execute, null: false, default: false
      t.boolean :order_only, null: false, default: false
      t.boolean :backdated_billing, null: false, default: false
      t.jsonb :execution_result

      t.timestamps
    end

    create_table :order_form_catalog_references, id: false, primary_key: %i[order_form_id referenced_type referenced_id] do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :order_form, null: false, foreign_key: true, type: :uuid
      t.string :referenced_type, null: false
      t.uuid :referenced_id, null: false

      t.timestamps
    end

    add_index :order_form_catalog_references, [:referenced_type, :referenced_id],
      name: :index_order_form_catalog_references_on_referenced_type_and_id

    create_table :order_form_attachments, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :order_form, null: false, foreign_key: true, type: :uuid
      t.string :file_name, null: false
      t.string :file_type, null: false
      t.string :file_url, null: false
      t.integer :file_size, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
