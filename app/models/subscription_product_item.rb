# frozen_string_literal: true

class SubscriptionProductItem < ApplicationRecord
  include PaperTrailTraceable
  include Discard::Model

  self.discard_column = :deleted_at

  belongs_to :organization
  belongs_to :subscription
  belongs_to :product_item

  has_many :rate_phases

  validates :billing_anchor_date, presence: true
  validates :next_billing_at, presence: true
  validates :started_at, presence: true
  validates :product_item_id, uniqueness: {scope: :subscription_id, conditions: -> { where(deleted_at: nil, ended_at: nil) }}

  validate :validate_started_before_ended

  default_scope -> { kept }

  private

  def validate_started_before_ended
    return if started_at.blank? || ended_at.blank?
    return if started_at <= ended_at

    errors.add(:ended_at, :must_be_after_started_at)
  end
end

# == Schema Information
#
# Table name: subscription_product_items
# Database name: primary
#
#  id                  :uuid             not null, primary key
#  billing_anchor_date :date             not null
#  deleted_at          :datetime
#  ended_at            :datetime
#  next_billing_at     :datetime         not null
#  started_at          :datetime         not null
#  units               :decimal(30, 10)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  organization_id     :uuid             not null
#  product_item_id     :uuid             not null
#  subscription_id     :uuid             not null
#
# Indexes
#
#  idx_spi_billable                                         (next_billing_at) WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_active_subscription_product_items_on_sub_and_item  (subscription_id,product_item_id) UNIQUE WHERE ((deleted_at IS NULL) AND (ended_at IS NULL))
#  index_subscription_product_items_on_deleted_at           (deleted_at)
#  index_subscription_product_items_on_organization_id      (organization_id)
#  index_subscription_product_items_on_product_item_id      (product_item_id)
#  index_subscription_product_items_on_subscription_id      (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (product_item_id => product_items.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
