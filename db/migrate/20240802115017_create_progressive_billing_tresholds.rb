# frozen_string_literal: true

class CreateProgressiveBillingTresholds < ActiveRecord::Migration[7.1]
  def change
    create_table :progressive_billing_tresholds, id: :uuid do |t|
      t.references :plan, null: false, index: true, foreign_key: true, type: :uuid
      t.string :treshold_display_name
      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false
      t.boolean :recurring, null: false, default: false

      t.timestamps
    end

    add_index :progressive_billing_tresholds, %i[amount_cents plan_id recurring], unique: true
    add_index :progressive_billing_tresholds, %i[recurring plan_id], unique: true, where: "recurring is true"
  end
end
