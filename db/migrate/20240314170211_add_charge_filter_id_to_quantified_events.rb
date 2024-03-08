# frozen_string_literal: true

class AddChargeFilterIdToQuantifiedEvents < ActiveRecord::Migration[7.0]
  class BillableMetricFilter < ApplicationRecord
  end

  class ChargeFilter < ApplicationRecord
    has_many :values, class_name: 'ChargeFilterValue'
  end

  class ChargeFilterValue < ApplicationRecord
    belongs_to :charge_filter
    belongs_to :billable_metric_filter
  end

  class QuantifiedEvent < ApplicationRecord
    include Discard::Model
    self.discard_column = :deleted_at
    default_scope -> { kept }

    belongs_to :group, optional: true
    belongs_to :billable_metric
  end

  def up
    # NOTE: Associate quantified_events with charge filters
    QuantifiedEvent.where.associated(:group).find_each do |event|
      filters = ChargeFilter.where(charge_id: event.billable_metric.charges.pluck(:id))

      object_hash = { event.group.key => [event.group.value] }
      object_hash[event.group.parent.key] = [event.group.parent.value] if event.group.parent

      filter = filters.find { |f| f.to_h == object_hash }

      event.update!(charge_filter_id: filter.id)
    end

    # NOTE: Associate adjusted_fees with charge filters
    AdjustedFee.where.associated(:group).find_each do |fee|
      object_hash = { fee.group.key => [fee.group.value] }
      object_hash[fee.group.parent.key] = [fee.group.parent.value] if fee.group.parent

      filter = filters.find { |f| f.to_h == object_hash }

      fee.update!(charge_filter_id: filter.id)
    end
  end

  def down; end
end
