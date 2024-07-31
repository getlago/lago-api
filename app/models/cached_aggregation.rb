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
end

# == Schema Information
#
# Table name: cached_aggregations
#
#  id                             :uuid             not null, primary key
#  current_aggregation            :decimal(, )
#  current_amount                 :decimal(, )
#  grouped_by                     :jsonb            not null
#  max_aggregation                :decimal(, )
#  max_aggregation_with_proration :decimal(, )
#  timestamp                      :datetime         not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  charge_filter_id               :uuid
#  charge_id                      :uuid             not null
#  event_id                       :uuid
#  event_transaction_id           :string
#  external_subscription_id       :string           not null
#  group_id                       :uuid
#  organization_id                :uuid             not null
#
# Indexes
#
#  index_cached_aggregations_on_charge_id                 (charge_id)
#  index_cached_aggregations_on_event_id                  (event_id)
#  index_cached_aggregations_on_event_transaction_id      (organization_id,event_transaction_id)
#  index_cached_aggregations_on_external_subscription_id  (external_subscription_id)
#  index_cached_aggregations_on_group_id                  (group_id)
#  index_cached_aggregations_on_organization_id           (organization_id)
#  index_timestamp_filter_lookup                          (organization_id,timestamp,charge_id,charge_filter_id)
#  index_timestamp_group_lookup                           (organization_id,timestamp,charge_id,group_id)
#  index_timestamp_lookup                                 (organization_id,timestamp,charge_id)
#
# Foreign Keys
#
#  fk_rails_...  (group_id => groups.id)
#
