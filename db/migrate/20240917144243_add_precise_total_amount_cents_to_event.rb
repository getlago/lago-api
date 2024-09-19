# frozen_string_literal: true

class AddPreciseTotalAmountCentsToEvent < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :precise_total_amount_cents, :decimal, precision: 40, scale: 15
  end
end
