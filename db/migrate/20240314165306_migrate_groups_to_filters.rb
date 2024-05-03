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
      filters = ::BillableMetricFilter.where(
        billable_metric_id: group.billable_metric_id,
        key: group.key,
      )
      filters = if group.deleted_at.present?
        filters.where.not(deleted_at: nil)
      else
        filters.where(deleted_at: nil)
      end

      filter = filters.first
      filter ||= ::BillableMetricFilter.new(
        billable_metric_id: group.billable_metric_id,
        key: group.key,
      )
      filter.deleted_at = group.deleted_at if group.deleted_at.present?

      filter.values ||= []
      filter.values << group.value

      filter.values.uniq!
      filter.save!
    rescue => e
      puts "#group_id: #{group.id} #{e.message}" # rubocop:disable Rails/Output
    end

    # NOTE: Only takes BM with groups into account
    bm_ids = Group.select(:billable_metric_id).distinct

    # NOTE: For each charge, we create charge filters with the same values
    Charge.joins(:billable_metric).where(billable_metrics: { id: bm_ids }).find_each do |charge|
      migrated_groups = []

      charge.group_properties.each do |property|
        # NOTE: Convert group properties to charge filters
        filter = charge.filters.create!(
          invoice_display_name: property.invoice_display_name,
          properties: property.values,
          deleted_at: property.deleted_at,
        )

        group = property.group
        migrated_groups << group
        bm_filters = BillableMetricFilter.where(
          billable_metric_id: group.billable_metric_id,
          key: group.key,
        )
        bm_filter = if group.deleted_at.present?
          bm_filters.where.not(deleted_at: nil).first
        else
          bm_filters.where(deleted_at: nil).first
        end

        # NOTE: Create filter value
        filter.values.create!(
          billable_metric_filter_id: bm_filter.id,
          values: [group.value],
          deleted_at: group.deleted_at,
        )

        next unless group.parent_group_id?

        # NOTE: When two dimensions, we create a filter value for the parent
        parent_bm_filters = BillableMetricFilter.where(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )
        parent_bm_filter = if group.parent.deleted_at.present?
          parent_bm_filters.where.not(deleted_at: nil).first
        else
          parent_bm_filters.where(deleted_at: nil).first
        end

        filter.values.create!(
          billable_metric_filter_id: parent_bm_filter.id,
          values: [group.parent.value],
          deleted_at: group.parent.deleted_at,
        )
      end

      # NOTE: Create filter values for the remaining groups
      charge.billable_metric.groups.where.not(id: migrated_groups.map(&:id)).includes(:children).find_each do |group|
        next if group.children.any?

        # Create charge filter
        filter = charge.filters.create!(properties: charge.properties, deleted_at: group.deleted_at)

        # Create filter values
        bm_filters = BillableMetricFilter.where(
          billable_metric_id: group.billable_metric_id,
          key: group.key,
        )
        bm_filter = if group.deleted_at.present?
          bm_filters.where.not(deleted_at: nil).first
        else
          bm_filters.where(deleted_at: nil).first
        end
        filter.values.create!(
          billable_metric_filter_id: bm_filter.id,
          values: [group.value],
          deleted_at: group.deleted_at,
        )

        next unless group.parent_group_id?

        parent_bm_filters = BillableMetricFilter.where(
          billable_metric_id: group.parent.billable_metric_id,
          key: group.parent.key,
        )
        parent_bm_filter = if group.parent.deleted_at.present?
          parent_bm_filters.where.not(deleted_at: nil).first
        else
          parent_bm_filters.where(deleted_at: nil).first
        end

        filter.values.create!(
          billable_metric_filter_id: parent_bm_filter.id,
          values: [group.parent.value],
          deleted_at: group.parent.deleted_at,
        )
      end
    rescue => e
      puts "#charge_id: #{charge.id} #{e.message}" # rubocop:disable Rails/Output
    end
  end

  def down
  end
end
