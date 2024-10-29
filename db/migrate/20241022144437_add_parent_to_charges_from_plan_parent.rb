# frozen_string_literal: true

class AddParentToChargesFromPlanParent < ActiveRecord::Migration[7.1]
  class Plan < ApplicationRecord
    has_many :charges, dependent: :destroy
    belongs_to :parent, class_name: 'Plan', optional: true
  end

  class Charge < ApplicationRecord
    belongs_to :plan
    belongs_to :parent, class_name: 'Charge', optional: true
  end

  def up
    now = Time.current
    Plan.where.not(parent_id: nil).includes(:charges, parent: :charges).find_each do |plan|
      parent = plan.parent
      next if plan.charges.empty? || parent.charges.empty?

      plan.charges.each do |child_charge|
        next if child_charge.parent_id.present?

        matches_without_properties = parent.charges.select do |charge|
          charge.charge_model == child_charge.charge_model &&
            charge.billable_metric_id == child_charge.billable_metric_id
        end
        full_matches = matches_without_properties.select do |charge|
          charge.properties == child_charge.properties
        end
        if full_matches.length == 1
          child_charge.update_columns(parent_id: full_matches[0].id) # rubocop:disable Rails/SkipsModelValidations
        elsif matches_without_properties.length == 1
          child_charge.update_columns(parent_id: matches_without_properties[0].id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
    Rails.logger.info('=' * 80)
    Rails.logger.info('Migration took: ' + (Time.current - now).to_s + ' seconds')
  end

  def down
  end
end
