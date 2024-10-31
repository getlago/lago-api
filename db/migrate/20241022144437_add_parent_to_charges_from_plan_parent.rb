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
    parents_count = Plan.where(parent_id: nil).count
    children_count = Plan.where.not(parent_id: nil).count
    if parents_count < children_count
      parents_less_than_children_migration
    else
      children_less_than_parents_migration
    end
  end

  def down
  end

  def parents_less_than_children_migration
    now = Time.current
    # another way to solve it - load parents, for charges find full matches in children plans and update parent_id
    # then if there are no matching charges in parent plan (with different properties) - select charges for children with
    # similar attributes, ignoring properties
    Plan.includes(:charges, children: :charges).where(parent_id: nil).find_each(batch_size: 250) do |parent_plan|
      next if parent_plan.children.empty?
      next if parent_plan.charges.empty?

      parent_plan.charges.each do |parent_charge|
        next if charge_has_copy?(parent_charge, parent_plan, :full)

        # process full match children
        full_match_ids = parent_plan.children.map(&:charges).flatten.select do |child_charge|
          child_charge.parent_id.nil? &&
            child_charge.charge_model == parent_charge.charge_model &&
            child_charge.billable_metric_id == parent_charge.billable_metric_id &&
            child_charge.properties == parent_charge.properties
        end.map(&:id)
        Charge.where(id: full_match_ids).update_all(parent_id: parent_charge.id)

        # process matching without properties
        next if charge_has_copy?(parent_charge, parent_plan, :without_properties)

        partial_match_id = parent_plan.children.map(&:charges).flatten.select do |child_charge|
          child_charge.parent_id.nil? &&
            child_charge.charge_model == parent_charge.charge_model &&
            child_charge.billable_metric_id == parent_charge.billable_metric_id
        end.map(&:id)
        Charge.where(id: partial_match_id).update_all(parent_id: parent_charge.id)
      end
    end
    puts 'Migration took: ' + (Time.current - now).to_s + ' seconds'
  end

  def charge_has_copy?(parent_charge, parent_plan, mode)
    if mode == :full
      parent_plan.charges.select do |charge|
        charge.charge_model == parent_charge.charge_model &&
          charge.billable_metric_id == parent_charge.billable_metric_id &&
          charge.properties == parent_charge.properties
      end.length > 1
    elsif mode == :without_properties
      parent_plan.charges.select do |charge|
        charge.charge_model == parent_charge.charge_model &&
          charge.billable_metric_id == parent_charge.billable_metric_id
      end.length > 1
    end
  end

  def children_less_than_parents_migration
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
        full_matches = parent.charges.select do |charge|
          charge.charge_model == child_charge.charge_model &&
            charge.billable_metric_id == child_charge.billable_metric_id &&
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
