# frozen_string_literal: true

class MonetizeFields < ActiveRecord::Migration[7.0]
  def change
    change_column :plans, :amount_cents, :integer, null: false, limit: 8
    change_column :charges, :amount_cents, :integer, null: false, limit: 8
  end
end
