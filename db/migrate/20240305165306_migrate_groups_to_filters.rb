# frozen_string_literal: true

class MigrateGroupsToFilters < ActiveRecord::Migration[7.0]
  class BillableMetricFilter < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at
    default_scope -> { kept }

    belongs_to :billable_metric
  end

  class Group < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at
    default_scope -> { kept }

    belongs_to :billable_metric, -> { with_discarded }
    belongs_to :parent, -> { with_discarded }, class_name: 'Group', foreign_key: 'parent_group_id', optional: true
  end

  class Charge < ApplicationRecord
    has_many :group_properties, dependent: :destroy
    belongs_to :billable_metric, -> { with_discarded }
    has_many :filters, dependent: :destroy, class_name: 'ChargeFilter'
    has_many :filter_values, through: :filters, class_name: 'ChargeFilterValue', source: :values
  end

  class BillableMetric < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at
    default_scope -> { kept }

    has_many :groups, dependent: :delete_all
    has_many :filters, -> { order(:key) }, dependent: :delete_all, class_name: 'BillableMetricFilter'
  end

  class ChargeFilter < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at
    default_scope -> { kept }

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
      filter.values << group.value unless filter.values.include?(group.value)
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
        filter.values.create!(billable_metric_filter_id: bm_filter.id, value: group.value)

        next unless group.parent_group_id?

        # NOTE: When two dimensions, we create a filter value for the parent
        parent_bm_filter = BillableMetricFilter.find_by(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )

        filter.values.create!(billable_metric_filter_id: parent_bm_filter.id, value: group.parent.value)
      end

      # NOTE: Create filter values for the remaining groups
      (charge.billable_metric.groups.where.not(parent_group_id: nil) - migrated_groups).each do |group|
        # Create charge filter
        filter = charge.filters.create!(
          invoice_display_name: charge.invoice_display_name,
          properties: charge.properties,
        )

        # Create filter values
        bm_filter = BillableMetricFilter.find_by(billable_metric_id: group.billable_metric_id, key: group.key)
        filter.values.create!(billable_metric_filter_id: bm_filter.id, value: group.value)

        next unless group.parent_group_id?

        parent_bm_filter = BillableMetricFilter.find_by(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )

        filter.values.create!(billable_metric_filter_id: parent_bm_filter.id, value: group.parent.value)
      end
    end
  end

  def down; end
end
