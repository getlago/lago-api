# frozen_string_literal: true

class AddExternalIdsToEvents < ActiveRecord::Migration[7.0]
  def change
    change_table :events, bulk: true do |t|
      t.string :external_customer_id
      t.string :external_subscription_id
      t.decimal :value
    end
  end
end
