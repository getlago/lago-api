class CreateSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :subscriptions, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true
      t.references :plan, type: :uuid, null: false, foreign_key: true, index: true

      t.integer :status, null: false

      t.timestamp :canceled_at
      t.timestamp :terminated_at
      t.timestamp :started_at

      t.timestamps
    end
  end
end
