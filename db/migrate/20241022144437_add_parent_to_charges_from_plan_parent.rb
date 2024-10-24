# frozen_string_literal: true
#
class AddParentToChargesFromPlanParent < ActiveRecord::Migration[7.1]
  def up
    now = Time.current
    Plan.where.not(parent_id: nil).includes(:charges, parent: :charges).find_each do |plan|
      parent = plan.parent
      next if plan.charges.empty? || parent.charges.empty?

      plan.charges.each do |child_charge|
        parent_charges = parent.charges.select do |charge|
          charge.charge_model == child_charge.charge_model && charge.properties == child_charge.properties
        end
        next if parent_charges.length != 1

        child_charge.update_columns(parent_id: parent_charges[0].id)
      end
    end
    puts '=' * 80
    puts 'Migration took: ' + (Time.current - now).to_s + ' seconds'
  end

  def down
  end
end
