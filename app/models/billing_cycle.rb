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
  belongs_to :invoice, optional: true

  enum :status, STATUSES, validate: true

  validates :billing_at, presence: true
  validates :period_from, presence: true
  validates :period_to, presence: true
end
