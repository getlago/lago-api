# frozen_string_literal: true

class ChangeFeesGroupedByType < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :fees, bulk: true do |t|
        t.remove :grouped_by
        t.jsonb :grouped_by, null: false, default: {}
      end

      change_table :cached_aggregations, bulk: true do |t|
        t.remove :grouped_by
        t.jsonb :grouped_by, null: false, default: {}
      end
    end
  end

  def down
    change_table :fees, bulk: true do |t|
      t.remove :grouped_by
      t.string :grouped_by, null: false, array: true, default: []
    end

    change_table :cached_aggregations, bulk: true do |t|
      t.remove :grouped_by
      t.string :grouped_by, null: false, array: true, default: []
    end
  end
end
