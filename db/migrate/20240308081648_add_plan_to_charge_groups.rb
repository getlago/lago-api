# frozen_string_literal: true

class AddPlanToChargeGroups < ActiveRecord::Migration[7.0]
  def change
    add_reference :charge_groups, :plan, foreign_key: true, type: :uuid
  end
end
