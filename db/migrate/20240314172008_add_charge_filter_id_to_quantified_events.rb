# frozen_string_literal: true

class AddChargeFilterIdToQuantifiedEvents < ActiveRecord::Migration[7.0]
  class BillableMetricFilter < ApplicationRecord
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

  class QuantifiedEvent < ApplicationRecord
    belongs_to :group, optional: true
    belongs_to :billable_metric
  end

  def up
    # NOTE: Associate quantified_events with charge filters
    QuantifiedEvent.where.associated(:group).find_each do |event|
      filters = ChargeFilter.where(charge_id: event.billable_metric.charges.pluck(:id))

      object_hash = { event.group.key => [event.group.value] }
      object_hash[event.group.parent.key] = [event.group.parent.value] if event.group.parent

      # First look for an active filter
      filter = filters.find do |f|
        next if f.deleted_at

        f_h = f.to_h
        f_h.keys == object_hash.keys && f_h.all? { |k, v| object_hash[k].sort == v.sort }
      end

      # If no active filter is found, look for a deleted filter
      filter ||= filters.find do |f|
        next unless f.deleted_at

        f_h = f.to_h
        f_h.keys == object_hash.keys && f_h.all? { |k, v| object_hash[k].sort == v.sort }
      end

      event.update!(charge_filter_id: filter.id)
    end
  end

  def down; end
end
