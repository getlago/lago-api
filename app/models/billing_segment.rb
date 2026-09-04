# frozen_string_literal: true

class BillingSegment < ApplicationRecord
  MICROSECOND = Rational(1, 1_000_000)

  def self.inclusive_end(instant) = instant - MICROSECOND

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
  validates :cycle_started_at, presence: true
  validates :started_at, presence: true
  validates :ended_at, presence: true
  validates :proration_ratio, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1}

  def rate
    rate_override || rate_card_rate
  end

  # The cadence this segment was billed on.
  def billing_interval
    Billing::Interval.from(rate_card_rate, override: rate_override)
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
# Table name: billing_segments
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  attempts                  :integer          default(0), not null
#  billing_at                :datetime         not null
#  cycle_started_at          :datetime         not null
#  ended_at                  :datetime         not null
#  proration_ratio           :decimal(30, 10)  default(1.0), not null
#  rate_properties           :jsonb            not null
#  started_at                :datetime         not null
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
#  billing_segments_no_overlapping_windows                       (organization_id, subscription_id, customer_id, subscription_rate_card_id, tsrange(started_at, ended_at, '[]'::text)) USING gist
#  idx_on_subscription_id_billing_at_status_943e595a4d           (subscription_id,billing_at,status)
#  idx_on_subscription_rate_card_id_cycle_started_at_23c80567e3  (subscription_rate_card_id,cycle_started_at)
#  index_billing_segments_on_card_and_start                      (subscription_rate_card_id,started_at) UNIQUE
#  index_billing_segments_on_customer_id                         (customer_id)
#  index_billing_segments_on_invoice_id                          (invoice_id)
#  index_billing_segments_on_organization_id                     (organization_id)
#  index_billing_segments_on_pricing_unit_id                     (pricing_unit_id)
#  index_billing_segments_on_rate_card_rate_id                   (rate_card_rate_id)
#  index_billing_segments_on_rate_override_id                    (rate_override_id)
#  index_billing_segments_on_subscription_id                     (subscription_id)
#  index_billing_segments_on_subscription_rate_card_id           (subscription_rate_card_id)
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
