# frozen_string_literal: true

class AddGroupIdToFees < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :fees, :group, type: :uuid, null: true, foreign_key: true, index: true
    end
  end
end
