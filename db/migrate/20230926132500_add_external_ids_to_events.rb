# frozen_string_literal: true

class AddExternalIdsToEvents < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :events, bulk: true do |t|
        t.string :external_customer_id
        t.string :external_subscription_id
      end

      change_column_null :events, :customer_id, true
    end
  end
end
