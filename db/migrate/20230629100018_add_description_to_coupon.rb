# frozen_string_literal: true

class AddDescriptionToCoupon < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :description, :text, null: true
  end
end
