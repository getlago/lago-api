# frozen_string_literal: true

class CreateOrderForms < ActiveRecord::Migration[8.0]
  def change
    create_enum :order_form_status, %w[generated signed expired voided]
    create_enum :order_form_void_reason, %w[manual expired invalid]

    create_table :order_forms, id: :uuid do |t|
      t.references :organization,
        null: false,
        foreign_key: true,
        type: :uuid
      t.references :customer,
        null: false,
        foreign_key: true,
        type: :uuid
      t.references :quote_version,
        null: false,
        foreign_key: true,
        index: {unique: true},
        type: :uuid
      t.references :signed_by_user,
        foreign_key: {to_table: :users},
        index: false,
        type: :uuid

      t.string :number, null: false

      t.enum :status,
        enum_type: :order_form_status,
        null: false,
        default: "generated"
      t.enum :void_reason, enum_type: :order_form_void_reason

      t.jsonb :billing_snapshot, null: false
      t.text :content
      t.text :legal_text

      t.datetime :expires_at
      t.datetime :signed_at
      t.datetime :voided_at

      t.timestamps

      t.index [:organization_id, :number],
        name: "index_order_forms_on_organization_id_and_number"
    end
  end
end
