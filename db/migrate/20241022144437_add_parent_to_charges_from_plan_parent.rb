# frozen_string_literal: true

class AddParentToChargesFromPlanParent < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  class Plan < ApplicationRecord
    has_many :charges, dependent: :destroy
    belongs_to :parent, class_name: 'Plan', optional: true
    has_many :children, class_name: 'Plan', foreign_key: :parent_id, dependent: :destroy
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
    Plan.where(parent_id: nil).includes(:charges, children: :charges).find_each(batch_size: 500) do |parent_plan|
      next if parent_plan.children.empty?
      next if parent_plan.charges.empty?

      parent_plan.charges.each do |parent_charge|
        assign_children_for_parent_charge(parent_charge, parent_plan.children, parent_plan)
      end
    end
  end

  def children_less_than_parents_migration
    Plan.where.not(parent_id: nil).order(:parent_id).includes(:charges, parent: :charges).in_batches(of: 2000).each do |plans_group|
      plans_group.group_by(&:parent).each do |parent_plan, children_plans|
        parent_plan.charges.each do |parent_charge|
          assign_children_for_parent_charge(parent_charge, children_plans, parent_plan)
        end
      end
    end
  end

  # find full matches in children plans and update parent_id (use update_all to not have separate requests)
  # then if there are no similar charges in parent plan (having different properties) - select charges for children with
  # similar attributes, ignoring the properties
  def assign_children_for_parent_charge(parent_charge, children_plans, parent_plan)
    return if charge_has_copy?(parent_charge, parent_plan, :full)

    children_charges = children_plans.flat_map(&:charges)
    # find full charge matches
    full_match_ids = children_charges.select do |child_charge|
      child_charge.parent_id.nil? &&
        child_charge.charge_model == parent_charge.charge_model &&
        child_charge.billable_metric_id == parent_charge.billable_metric_id &&
        child_charge.properties == parent_charge.properties
    end.map(&:id)

    # find matching charges without properties
    partial_match_ids = []
    unless charge_has_copy?(parent_charge, parent_plan, :without_properties)
      partial_match_ids = children_charges.select do |child_charge|
        child_charge.parent_id.nil? &&
          child_charge.charge_model == parent_charge.charge_model &&
          child_charge.billable_metric_id == parent_charge.billable_metric_id
      end.map(&:id)
    end

    # write only once for all children charges
    Charge.where(id: full_match_ids.concat(partial_match_ids)).update_all(parent_id: parent_charge.id) # rubocop:disable Rails/SkipsModelValidations
  end

  def charge_has_copy?(parent_charge, parent_plan, mode)
    if mode == :full
      parent_plan.charges.any? do |charge|
        charge.charge_model == parent_charge.charge_model &&
          charge.billable_metric_id == parent_charge.billable_metric_id &&
          charge.properties == parent_charge.properties &&
          charge.id != parent_charge.id
      end
    elsif mode == :without_properties
      parent_plan.charges.any? do |charge|
        charge.charge_model == parent_charge.charge_model &&
          charge.billable_metric_id == parent_charge.billable_metric_id &&
          charge.id != parent_charge.id
      end
    end
  end
end
