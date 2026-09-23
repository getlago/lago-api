# frozen_string_literal: true

# A durable priced slice of a contract rate card billing cycle. A whole cycle has one
# segment; a rate change inside the cycle creates several segments sharing cycle_started_at.
class BillingSegment < ApplicationRecord
  include Currencies

  MICROSECOND = Rational(1, 1_000_000)

  # Schedule windows have exclusive ends; the database overlap constraint uses inclusive ends.
  def self.inclusive_end(instant) = instant - MICROSECOND

  def self.exclusive_end(instant) = instant + MICROSECOND

  STATUSES = {
    pending: "pending",
    processing: "processing",
    done: "done",
    failed: "failed"
  }.freeze

  belongs_to :organization
  belongs_to :contract
  belongs_to :customer, -> { with_discarded }
  belongs_to :contract_rate_card, -> { with_discarded }
  belongs_to :invoice, optional: true
  belongs_to :rate_card_rate, -> { with_discarded }, optional: true
  belongs_to :rate_override, -> { with_discarded }, optional: true
  belongs_to :pricing_unit, optional: true

  enum :status, STATUSES, validate: true, prefix: true

  # What the periodic consumer still owes an invoice for. One name for both ends of the pipe:
  # the clock selects customers by it and the consumer selects their segments by it, so
  # neither can drift into offering work the other will not do.
  #
  # Metered usage billed in advance is priced per event rather than on the tick, so its
  # segments are never invoiced here and never leave their state. Selecting them would
  # enqueue that customer every hour for a run with nothing to do.
  scope :awaiting_invoicing, -> {
    where(status: [:pending, :processing])
      .joins(contract_rate_card: {rate_card: :product})
      .where(
        "products.product_type != :metered OR rate_cards.billing_timing != :advance",
        metered: Product::PRODUCT_TYPES[:metered],
        advance: RateCard::BILLING_TIMINGS[:advance]
      )
  }

  validates :billing_at, presence: true
  validates :cycle_started_at, presence: true
  validates :currency, presence: true, inclusion: {in: currency_list, allow_nil: true}
  validates :started_at, presence: true
  validates :ended_at, presence: true
  validates :proration_ratio, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1}

  validate :validate_rate_presence
  validate :validate_period_bounds
  validate :validate_cycle_bounds

  def rate
    rate_override || rate_card_rate
  end

  def target_key
    "contract-#{contract_id}-#{contract_rate_card.product.target_key}"
  end

  # The shared matcher expects a filter object for the default bucket, not nil.
  # This mirrors the empty ChargeFilter in app/services/fees/charge_service.rb:85-95.
  def empty_product_filter
    ProductFilter.new(organization:, product: contract_rate_card.rate_card.product)
  end

  def duration_in_days
    Billing::Days.between(
      started_at,
      BillingSegment.exclusive_end(ended_at),
      timezone: customer.applicable_timezone
    )
  end

  # Elapsed progress is independent of the stored service-price proration_ratio.
  def elapsed_period_ratio(at: Time.current)
    timezone = customer.applicable_timezone

    Billing::ElapsedPeriodRatio.calculate(
      from_date: started_at.in_time_zone(timezone).to_date,
      to_date: ended_at.in_time_zone(timezone).to_date,
      current_date: at.in_time_zone(timezone).to_date,
      duration_in_days:
    )
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

  # Returns the prorated minimum in pricing-unit cents when configured, otherwise fiat cents.
  def prorated_min_amount_cents
    minimum = min_amount_cents.to_d * proration_ratio

    if pricing_unit
      minimum / Money::Currency.new(currency).subunit_to_unit /
        pricing_unit_conversion_rate * pricing_unit.subunit_to_unit.to_d
    else
      minimum
    end
  end

  private

  def validate_rate_presence
    if rate_card_rate || rate_override
      return
    end

    errors.add(:base, :rate_card_rate_or_rate_override_required)
  end

  def validate_period_bounds
    if started_at.blank? || ended_at.blank? || started_at <= ended_at
      return
    end

    errors.add(:ended_at, :must_be_after_started_at)
  end

  def validate_cycle_bounds
    if cycle_started_at.blank? || started_at.blank? || cycle_started_at <= started_at
      return
    end

    errors.add(:cycle_started_at, :must_be_before_started_at)
  end
end

# == Schema Information
#
# Table name: billing_segments
# Database name: primary
#
#  id                    :uuid             not null, primary key
#  billing_at            :datetime         not null
#  currency              :string           not null
#  cycle_started_at      :datetime         not null
#  ended_at              :datetime         not null
#  proration_ratio       :decimal(30, 10)  default(1.0), not null
#  rate_properties       :jsonb            not null
#  started_at            :datetime         not null
#  status                :enum             default("pending"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_id           :uuid             not null
#  contract_rate_card_id :uuid             not null
#  customer_id           :uuid             not null
#  invoice_id            :uuid
#  organization_id       :uuid             not null
#  pricing_unit_id       :uuid
#  rate_card_rate_id     :uuid
#  rate_override_id      :uuid
#
# Indexes
#
#  billing_segments_no_overlapping_periods                (organization_id, contract_id, customer_id, contract_rate_card_id, tsrange(started_at, ended_at, '[]'::text)) USING gist
#  idx_on_contract_id_billing_at_status_3588bfae7a        (contract_id,billing_at,status)
#  index_billing_segments_on_card_and_cycle               (contract_rate_card_id,cycle_started_at)
#  index_billing_segments_on_card_and_period              (contract_rate_card_id,started_at) UNIQUE
#  index_billing_segments_on_contract_id                  (contract_id)
#  index_billing_segments_on_contract_rate_card_id        (contract_rate_card_id)
#  index_billing_segments_on_customer_awaiting_invoicing  (status,customer_id) WHERE (status = ANY (ARRAY['pending'::billing_segment_status, 'processing'::billing_segment_status]))
#  index_billing_segments_on_customer_id                  (customer_id)
#  index_billing_segments_on_invoice_id                   (invoice_id)
#  index_billing_segments_on_organization_id              (organization_id)
#  index_billing_segments_on_rate_override_id             (rate_override_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (contract_rate_card_id => contract_rate_cards.id)
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (pricing_unit_id => pricing_units.id)
#  fk_rails_...  (rate_card_rate_id => rate_card_rates.id)
#  fk_rails_...  (rate_override_id => rate_overrides.id)
#
