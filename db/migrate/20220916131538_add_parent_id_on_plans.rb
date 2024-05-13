# frozen_string_literal: true

class AddParentIdOnPlans < ActiveRecord::Migration[7.0]
  def change
    add_reference :plans, :parent, type: :uuid, null: true, index: true, foreign_key: {to_table: :plans}
  end
end
