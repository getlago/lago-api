# frozen_string_literal: true

class AddNameToRatePhases < ActiveRecord::Migration[8.0]
  def change
    add_column :rate_phases, :name, :string
  end
end
