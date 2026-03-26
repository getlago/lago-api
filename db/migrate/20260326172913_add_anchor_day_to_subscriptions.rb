# frozen_string_literal: true

class AddAnchorDayToSubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :subscriptions, :anchor_date, :date
  end
end
