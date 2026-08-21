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
  belongs_to :customer, -> { with_discarded }
  belongs_to :subscription_rate_card, -> { with_discarded }
  belongs_to :invoice, optional: true
  belongs_to :rate_card_rate, -> { with_discarded }, optional: true
  belongs_to :rate_override, -> { with_discarded }, optional: true
  belongs_to :pricing_unit, optional: true

  enum :status, STATUSES, validate: true

  validates :billing_at, presence: true
  validates :period_from, presence: true
  validates :period_to, presence: true
  validates :proration_ratio, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1}

  def rate
    rate_override || rate_card_rate
  end

  def currency
    rate_card_rate.rate_card.currency
  end

  def pricing_unit_conversion_rate
    if rate_override
      rate_override.pricing_unit_conversion_rate
    else
      rate_card_rate.applied_pricing_unit_conversion_rate
    end
  end

  def min_amount_cents
    if rate_override
      rate_override.min_amount_cents
    else
      rate_card_rate.min_amount_cents
    end
  end
end

# == Schema Information
#
# Table name: billing_cycles
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  attempts                  :integer          default(0), not null
#  billing_at                :datetime         not null
#  period_from               :datetime         not null
#  period_to                 :datetime         not null
#  proration_ratio           :decimal(30, 10)  default(1.0), not null
#  rate_properties           :jsonb            not null
#  status                    :enum             default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  customer_id               :uuid             not null
#  invoice_id                :uuid
#  organization_id           :uuid             not null
#  pricing_unit_id           :uuid
#  rate_card_rate_id         :uuid
#  rate_override_id          :uuid
#  subscription_id           :uuid             not null
#  subscription_rate_card_id :uuid             not null
#
# Indexes
#
#  billing_cycles_no_overlapping_periods                (organization_id, subscription_id, customer_id, subscription_rate_card_id, tsrange(period_from, period_to, '[]'::text)) USING gist
#  idx_on_subscription_id_billing_at_status_a01115903b  (subscription_id,billing_at,status)
#  index_billing_cycles_on_customer_id                  (customer_id)
#  index_billing_cycles_on_invoice_id                   (invoice_id)
#  index_billing_cycles_on_organization_id              (organization_id)
#  index_billing_cycles_on_pricing_unit_id              (pricing_unit_id)
#  index_billing_cycles_on_product_and_period           (subscription_rate_card_id,period_from) UNIQUE
#  index_billing_cycles_on_rate_card_rate_id            (rate_card_rate_id)
#  index_billing_cycles_on_rate_override_id             (rate_override_id)
#  index_billing_cycles_on_subscription_id              (subscription_id)
#  index_billing_cycles_on_subscription_rate_card_id    (subscription_rate_card_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (pricing_unit_id => pricing_units.id)
#  fk_rails_...  (rate_card_rate_id => rate_card_rates.id)
#  fk_rails_...  (rate_override_id => rate_overrides.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#  fk_rails_...  (subscription_rate_card_id => subscription_rate_cards.id)
#
