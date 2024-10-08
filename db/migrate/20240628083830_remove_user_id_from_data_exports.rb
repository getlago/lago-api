# frozen_string_literal: true

class RemoveUserIdFromDataExports < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      remove_reference :data_exports, :user, null: false, foreign_key: true, type: :uuid
    end
  end
end
