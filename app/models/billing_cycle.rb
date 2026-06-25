# frozen_string_literal: true

# A durable billing-period row: the outbox + retry unit of the new billing engine.
# One per (subscription_product_item, period). The scheduler inserts it (status
# pending) while advancing the clock; the processor turns pending cycles into an
# invoice and marks them done. High-volume ledger — no soft delete, no PaperTrail.
class BillingCycle < ApplicationRecord
  STATUSES = {
    pending: "pending",
    processing: "processing",
    done: "done",
    failed: "failed"
  }.freeze

  belongs_to :organization
  belongs_to :subscription
  belongs_to :subscription_product_item

  enum :status, STATUSES, validate: true

  validates :billing_at, presence: true
  validates :period_from, presence: true
  validates :period_to, presence: true
end

# == Schema Information
#
# Table name: billing_cycles
# Database name: primary
#
#  id                           :uuid             not null, primary key
#  attempts                     :integer          default(0), not null
#  billing_at                   :datetime         not null
#  period_from                  :datetime         not null
#  period_to                    :datetime         not null
#  status                       :enum             default("pending"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  organization_id              :uuid             not null
#  subscription_id              :uuid             not null
#  subscription_product_item_id :uuid             not null
#
# Indexes
#
#  idx_on_subscription_id_billing_at_status_a01115903b   (subscription_id,billing_at,status)
#  index_billing_cycles_on_organization_id               (organization_id)
#  index_billing_cycles_on_product_item_and_period       (subscription_product_item_id,period_from) UNIQUE
#  index_billing_cycles_on_subscription_id               (subscription_id)
#  index_billing_cycles_on_subscription_product_item_id  (subscription_product_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (subscription_product_item_id => subscription_product_items.id)
#
