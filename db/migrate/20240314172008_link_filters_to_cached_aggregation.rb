# frozen_string_literal: true

class LinkFiltersToCachedAggregation < ActiveRecord::Migration[7.0]
  class BillableMetricFilter < ApplicationRecord
  end

  class ChargeFilter < ApplicationRecord
    has_many :values, class_name: 'ChargeFilterValue'
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
    belongs_to :group, -> { with_discarded }, optional: true
    belongs_to :charge, -> { with_discarded }, optional: true
    belongs_to :charge_filter, -> { with_discarded }, optional: true
  end

  class AdjustedFee < ApplicationRecord
    belongs_to :charge, optional: true
    belongs_to :group, optional: true
  end

  class QuantifiedEvent < ApplicationRecord
    belongs_to :group, optional: true
  end

  def up
    # NOTE: Associate cached aggregations with charge filters
    CachedAggregation.where.associated(:group).where(charge_filter_id: nil).find_each do |agg|
      link_charge_filter(agg)
    end

    # NOTE: Associate fees with charge filters
    Fee.where.associated(:group).where(charge_filter_id: nil).find_each do |fee|
      link_charge_filter(fee)
    end

    # NOTE: Associate adjusted fees with charge filters
    AdjustedFee.where.associated(:group).where(charge_filter_id: nil).find_each do |fee|
      link_charge_filter(fee)
    end
  end

  def down; end

  private

  def link_charge_filter(object)
    object_hash = { object.group.key => [object.group.value] }
    object_hash[object.group.parent.key] = [object.group.parent.value] if object.group.parent

    filter = object.charge.filters.find { |f| f.to_h == object_hash }

    object.update!(charge_filter_id: filter.id)
  end
end
