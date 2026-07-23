# frozen_string_literal: true

# A durable billing-period row: the outbox + retry unit of the new billing engine.
# One per (subscription_rate_card, period). The scheduler inserts it (status
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
  belongs_to :customer
  belongs_to :subscription_rate_card
  belongs_to :invoice, optional: true

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
#  customer_id                  :uuid             not null
#  invoice_id                   :uuid
#  organization_id              :uuid             not null
#  subscription_id              :uuid             not null
#  subscription_rate_card_id :uuid             not null
#
# Indexes
#
#  idx_on_subscription_id_billing_at_status_a01115903b   (subscription_id,billing_at,status)
#  index_billing_cycles_on_customer_id                   (customer_id)
#  index_billing_cycles_on_invoice_id                    (invoice_id)
#  index_billing_cycles_on_organization_id               (organization_id)
#  index_billing_cycles_on_product_item_and_period       (subscription_rate_card_id,period_from) UNIQUE
#  index_billing_cycles_on_subscription_id               (subscription_id)
#  index_billing_cycles_on_subscription_rate_card_id  (subscription_rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (subscription_rate_card_id => subscription_rate_cards.id)
#
