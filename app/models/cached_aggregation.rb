# frozen_string_literal: true

class CachedAggregation < ApplicationRecord
  belongs_to :organization
  belongs_to :charge
  belongs_to :group, optional: true
  belongs_to :charge_filter, optional: true

  validates :external_subscription_id, presence: true
  validates :timestamp, presence: true

  scope :from_datetime, ->(from_datetime) { where('cached_aggregations.timestamp::timestamp(0) >= ?', from_datetime) }
  scope :to_datetime, ->(to_datetime) { where('cached_aggregations.timestamp::timestamp(0) <= ?', to_datetime) }

  def current_aggregation_decimal
    BigDecimal(current_aggregation.to_s)
  end

  def max_aggregation_decimal
    BigDecimal(max_aggregation.to_s)
  end

  def units_applied_decimal
    BigDecimal(units_applied.to_s)
  end

  def current_amount_decimal
    BigDecimal(current_amount.to_s)
  end
end
