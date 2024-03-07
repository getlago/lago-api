# frozen_string_literal: true

class AddChargeFilterIdToQuantifiedEvents < ActiveRecord::Migration[7.0]
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
      filter = filters.find do |f|
        f.values.pluck(:value).sort == [event.group.value, event.group.parent&.value].compact.sort
      end

      event.update!(charge_filter_id: filter.id)
    end

    # NOTE: Associate adjusted_fees with charge filters
    AdjustedFee.where.associated(:group).find_each do |fee|
      filter = fee.charge.filters.find do |f|
        f.values.pluck(:value).sort == [fee.group.value, fee.group.parent&.value].compact.sort
      end

      fee.update!(charge_filter_id: filter.id)
    end
  end

  def down; end
end
