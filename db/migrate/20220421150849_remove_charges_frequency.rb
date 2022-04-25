# frozen_string_literal: true

class RemoveChargesFrequency < ActiveRecord::Migration[7.0]
  def change
    remove_column :charges, :frequency
  end
end
