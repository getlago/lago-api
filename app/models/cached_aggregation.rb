# frozen_string_literal: true

class CachedAggregation < ApplicationRecord
  self.ignored_columns += %w[event_id]

  belongs_to :organization
  belongs_to :charge, optional: true
  belongs_to :contract_rate_card, -> { with_discarded }, optional: true
  belongs_to :product_filter, -> { with_discarded }, optional: true
  belongs_to :group, optional: true
  belongs_to :charge_filter, optional: true

  validates :external_subscription_id, presence: true
  validates :timestamp, presence: true
  validates :charge, presence: true, unless: :contract_rate_card

  scope :from_datetime, ->(from_datetime) { where("cached_aggregations.timestamp >= ?", from_datetime&.change(usec: 0)) }
  scope :to_datetime, ->(to_datetime) { where("cached_aggregations.timestamp <= ?", to_datetime&.change(usec: 0)) }
end

# == Schema Information
#
# Table name: cached_aggregations
# Database name: primary
#
#  id                             :uuid             not null, primary key
#  current_aggregation            :decimal(, )
#  current_amount                 :decimal(, )
#  grouped_by                     :jsonb            not null
#  max_aggregation                :decimal(, )
#  max_aggregation_with_proration :decimal(, )
#  presentation_breakdowns        :jsonb            not null
#  timestamp                      :datetime         not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  charge_filter_id               :uuid
#  charge_id                      :uuid
#  contract_rate_card_id          :uuid
#  event_transaction_id           :string
#  external_subscription_id       :string           not null
#  group_id                       :uuid
#  organization_id                :uuid             not null
#  product_filter_id              :uuid
#
# Indexes
#
#  idx_aggregation_lookup                                 (external_subscription_id,charge_id,timestamp)
#  idx_cached_aggregation_contract_lookup                 (contract_rate_card_id,product_filter_id,timestamp DESC) WHERE (contract_rate_card_id IS NOT NULL)
#  idx_cached_aggregation_filtered_lookup                 (organization_id,external_subscription_id,charge_id,timestamp DESC,created_at DESC)
#  index_cached_aggregations_on_charge_id                 (charge_id)
#  index_cached_aggregations_on_event_transaction_id      (organization_id,event_transaction_id)
#  index_cached_aggregations_on_external_subscription_id  (external_subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (group_id => groups.id)
#  fk_rails_...  (product_filter_id => product_filters.id)
#
