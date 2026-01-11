# frozen_string_literal: true

class AddApplyAfterFinalizationToCredits < ActiveRecord::Migration[8.0]
  def change
    add_column :credits, :apply_after_finalization, :boolean, default: false, null: false
  end
end
