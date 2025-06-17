# frozen_string_literal: true

class CreatePaymentProviders < ActiveRecord::Migration[7.0]
  def change
    create_table :payment_providers, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.string :type, null: false
      t.string :secrets
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end
  end
end
