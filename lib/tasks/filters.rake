# frozen_string_literal: true

namespace :filters do
  desc 'Fill charge filter for resources linked to groups'
  task migrate: :environment do
    class BillableMetricFilter < ApplicationRecord
    end

    class Charge < ApplicationRecord
      has_many :filters, class_name: 'ChargeFilter'
    end

    class ChargeFilter < ApplicationRecord
      has_many :values, class_name: 'ChargeFilterValue'

      def to_h
        # NOTE: Ensure filters are keeping the initial ordering
        values.order(updated_at: :asc).each_with_object({}) do |filter_value, result|
          result[filter_value.billable_metric_filter.key] = filter_value.values
        end
      end
    end

    class ChargeFilterValue < ApplicationRecord
      belongs_to :charge_filter
      belongs_to :billable_metric_filter
    end

    class CachedAggregation < ApplicationRecord
      belongs_to :group, optional: true
      belongs_to :charge
    end

    class Fee < ApplicationRecord
      belongs_to :group, optional: true
      belongs_to :charge, optional: true
      belongs_to :charge_filter, optional: true
    end

    class AdjustedFee < ApplicationRecord
      belongs_to :charge, optional: true
      belongs_to :group, optional: true
    end

    class QuantifiedEvent < ApplicationRecord
      belongs_to :group, optional: true
    end

    def link_charge_filter(object)
      object_hash = {object.group.key => [object.group.value]}
      object_hash[object.group.parent.key] = [object.group.parent.value] if object.group.parent

      # First look for an active filter
      filter = object.charge.filters.find do |f|
        next if f.deleted_at

        f_h = f.to_h
        f_h.keys == object_hash.keys && f_h.all? { |k, v| object_hash[k].sort == v.sort }
      end

      # If no active filter is found, look for a deleted filter
      filter ||= object.charge.filters.find do |f|
        next unless f.deleted_at

        f_h = f.to_h
        f_h.keys == object_hash.keys && f_h.all? { |k, v| object_hash[k].sort == v.sort }
      end

      # If no filter is found, create a new one
      unless filter
        deleted_at = Time.current

        # NOTE: Group was removed
        filter = object.charge.filters.create!(
          invoice_display_name: object.group.key,
          properties: object.charge.properties,
          deleted_at:,
        )

        bm_filter = BillableMetricFilter.find_by(
          billable_metric_id: object.charge.billable_metric_id,
          key: object.group.key,
        )

        filter.values.create!(billable_metric_filter_id: bm_filter.id, values: [object.group.value], deleted_at:)

        if object.group.parent_group_id?
          parent_bm_filter = BillableMetricFilter.find_by(
            billable_metric_id: object.group.parent.billable_metric_id,
            key: object.group.parent.key,
          )

          filter.values.create!(
            billable_metric_filter_id: parent_bm_filter.id,
            values: [object.group.parent.value],
            deleted_at:,
          )
        end
      end

      # Assign the filter to the object
      object.update!(charge_filter_id: filter.id)
    end

    # NOTE: Associate cached aggregations with charge filters
    puts 'Migrate cached aggregations' # rubocop:disable Rails/Output
    CachedAggregation.where.associated(:group)
      .where(charge_filter_id: nil)
      .includes(charge: :filters, group: :parent)
      .find_each { |agg| link_charge_filter(agg) }

    # NOTE: Associate fees with charge filters
    puts 'Migrate fees' # rubocop:disable Rails/Output
    Fee.where.associated(:group)
      .where(charge_filter_id: nil)
      .includes(charge: :filters, group: :parent)
      .find_each { |fee| link_charge_filter(fee) }

    # NOTE: Associate adjusted fees with charge filters
    puts 'Migrate adjusted fees' # rubocop:disable Rails/Output
    AdjustedFee.where.associated(:group)
      .where(charge_filter_id: nil)
      .includes(charge: :filters, group: :parent)
      .find_each { |fee| link_charge_filter(fee) }
  end
end
