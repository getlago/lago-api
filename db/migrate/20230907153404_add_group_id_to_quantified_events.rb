# frozen_string_literal: true

class AddGroupIdToQuantifiedEvents < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_reference :quantified_events, :group, type: :uuid, foreign_key: true, index: true
      change_column_null :quantified_events, :external_id, true
    end
  end
end
