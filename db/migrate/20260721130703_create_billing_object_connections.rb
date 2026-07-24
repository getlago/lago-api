# frozen_string_literal: true

class CreateBillingObjectConnections < ActiveRecord::Migration[8.0]
  def change
    create_enum :billing_object_connection_behavior, %w[specific skip]

    create_table :billing_object_connections, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :owner, null: false, type: :uuid, polymorphic: true, index: false
      t.references :payment_provider_customer, foreign_key: true, type: :uuid
      t.references :integration_customer, foreign_key: true, type: :uuid

      t.enum :category, enum_type: :connection_category, null: false
      t.enum :behavior, enum_type: :billing_object_connection_behavior, null: false

      t.timestamps

      t.index [:owner_type, :owner_id, :category], unique: true
    end
  end
end
