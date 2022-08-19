class CreateAppliedPrepaidCredits < ActiveRecord::Migration[7.0]
  def change
    create_table :applied_prepaid_credits, id: :uuid do |t|
      t.references :invoice, type: :uuid, foreign_key: true, index: true
      t.references :wallet_transaction, type: :uuid, foreign_key: true, index: true

      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false

      t.timestamps
    end
  end
end
