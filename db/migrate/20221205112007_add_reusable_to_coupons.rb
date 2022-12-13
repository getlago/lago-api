# frozen_string_literal: true

class AddReusableToCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :reusable, :boolean, default: true, null: false
  end
end
