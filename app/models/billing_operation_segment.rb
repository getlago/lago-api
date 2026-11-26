# frozen_string_literal: true

class BillingOperationSegment < ApplicationRecord
  belongs_to :organization
  belongs_to :billing_operation, inverse_of: :segments
  belongs_to :rate_card_rate, -> { with_discarded }
  belongs_to :rate_override, -> { with_discarded }, optional: true

  validates :position, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :started_at, :ended_at, :proration_ratio, presence: true
  validates :ended_at, comparison: {greater_than: :started_at}, if: -> { started_at.present? && ended_at.present? }
  validate :tenant_and_source_match

  private

  def tenant_and_source_match
    return unless organization && billing_operation

    errors.add(:billing_operation, :invalid) if billing_operation.organization_id != organization_id
    errors.add(:rate_card_rate, :invalid) if rate_card_rate && (rate_card_rate.organization_id != organization_id ||
      rate_card_rate.rate_card_id != billing_operation.contract_rate_card.rate_card_id)
    errors.add(:rate_override, :invalid) if rate_override && rate_override.organization_id != organization_id
  end
end

# == Schema Information
#
# Table name: billing_operation_segments
# Database name: primary
#
#  id                   :uuid             not null, primary key
#  ended_at             :datetime         not null
#  position             :integer          not null
#  proration_ratio      :decimal(30, 10)  not null
#  started_at           :datetime         not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  billing_operation_id :uuid             not null
#  organization_id      :uuid             not null
#  rate_card_rate_id    :uuid             not null
#  rate_override_id     :uuid
#
# Indexes
#
#  idx_on_billing_operation_id_position_b8630a7f5c        (billing_operation_id,position) UNIQUE
#  index_billing_operation_segments_on_organization_id    (organization_id)
#  index_billing_operation_segments_on_rate_card_rate_id  (rate_card_rate_id)
#  index_billing_operation_segments_on_rate_override_id   (rate_override_id)
#
# Foreign Keys
#
#  fk_rails_...  (billing_operation_id => billing_operations.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (rate_card_rate_id => rate_card_rates.id)
#  fk_rails_...  (rate_override_id => rate_overrides.id)
#
