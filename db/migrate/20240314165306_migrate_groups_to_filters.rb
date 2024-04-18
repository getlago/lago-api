# frozen_string_literal: true

class MigrateGroupsToFilters < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  class BillableMetricFilter < ApplicationRecord
    belongs_to :billable_metric
  end

  class GroupProperty < ApplicationRecord
    belongs_to :group
    belongs_to :charge
  end

  class Group < ApplicationRecord
    belongs_to :billable_metric
    belongs_to :parent, class_name: 'Group', foreign_key: 'parent_group_id', optional: true
    has_many :children, class_name: 'Group', foreign_key: 'parent_group_id'
    has_many :properties, class_name: 'GroupProperty'
  end

  class Charge < ApplicationRecord
    has_many :group_properties
    belongs_to :billable_metric
    has_many :filters, class_name: 'ChargeFilter'
    has_many :filter_values, through: :filters, class_name: 'ChargeFilterValue', source: :values
  end

  class BillableMetric < ApplicationRecord
    has_many :groups
    has_many :filters, -> { order(:key) }, dependent: :delete_all, class_name: 'BillableMetricFilter'
  end

  class ChargeFilter < ApplicationRecord
    belongs_to :charge
    has_many :values, class_name: 'ChargeFilterValue', dependent: :destroy
  end

  def up
    # NOTE: For each group, we create a filter with the same key and values
    Group.find_each do |group|
      filter = ::BillableMetricFilter.find_or_initialize_by(
        billable_metric_id: group.billable_metric_id,
        key: group.key,
      )

      filter.values ||= []
      filter.values << group.value
      filter.values.uniq!
      filter.save!
    end

    # NOTE: For each charge, we create charge filters with the same values
    Charge.where.associated(:group_properties).distinct.find_each do |charge|
      migrated_groups = []

      charge.group_properties.each do |property|
        # NOTE: Convert group properties to charge filters
        filter = charge.filters.create!(
          invoice_display_name: property.invoice_display_name,
          properties: property.values,
        )

        group = property.group
        migrated_groups << group
        bm_filter = BillableMetricFilter.find_by(billable_metric_id: group.billable_metric_id, key: group.key)

        # NOTE: Create filter value
        filter.values.create!(billable_metric_filter_id: bm_filter.id, values: [group.value])

        next unless group.parent_group_id?

        # NOTE: When two dimensions, we create a filter value for the parent
        parent_bm_filter = BillableMetricFilter.find_by(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )

        filter.values.create!(billable_metric_filter_id: parent_bm_filter.id, values: [group.parent.value])
      end

      # NOTE: Create filter values for the remaining groups
      charge.billable_metric.groups.where.not(id: migrated_groups.map(&:id)).includes(:children).find_each do |group|
        next if group.children.any?

        # Create charge filter
        filter = charge.filters.create!(properties: charge.properties)

        # Create filter values
        bm_filter = BillableMetricFilter.find_by(billable_metric_id: group.billable_metric_id, key: group.key)
        filter.values.create!(billable_metric_filter_id: bm_filter.id, values: [group.value])

        next unless group.parent_group_id?

        parent_bm_filter = BillableMetricFilter.find_by(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )

        filter.values.create!(billable_metric_filter_id: parent_bm_filter.id, values: [group.parent.value])
      end
    end
  end

  def down; end
end
