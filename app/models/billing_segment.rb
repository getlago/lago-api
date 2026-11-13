# frozen_string_literal: true

# An in-memory priced slice of a contract rate card billing cycle.
class BillingSegment
  include Currencies

  MICROSECOND = Rational(1, 1_000_000)
  PRORATION_RATIO_TYPE = ActiveModel::Type::Decimal.new(precision: 30, scale: 10)

  ATTRIBUTES = %w[
    organization_id customer_id contract_id contract_rate_card_id rate_card_rate_id
    rate_override_id pricing_unit_id
    rate_properties currency started_at ended_at cycle_started_at billing_at proration_ratio billable_metric_code
  ].freeze

  attr_accessor :organization, :customer, :contract, :contract_rate_card, :rate_card_rate,
    :rate_override, :pricing_unit, :rate_properties, :currency, :started_at, :ended_at,
    :cycle_started_at, :billing_at, :billable_metric_code

  attr_reader :proration_ratio

  def self.inclusive_end(instant) = instant - MICROSECOND

  def self.exclusive_end(instant) = instant + MICROSECOND

  def self.from_attributes(attributes)
    attributes = attributes.to_h.symbolize_keys
    organization = Organization.find(attributes.fetch(:organization_id))
    attributes[:organization] = organization
    attributes[:customer] = organization.customers.with_discarded.find(attributes.fetch(:customer_id))
    attributes[:contract] = organization.contracts.find(attributes.fetch(:contract_id))
    attributes[:contract_rate_card] = ContractRateCard.with_discarded.where(organization:)
      .find(attributes.fetch(:contract_rate_card_id))
    attributes[:billable_metric_code] ||= attributes[:contract_rate_card].rate_card.product.billable_metric&.code
    attributes[:rate_card_rate] = organization.rate_card_rates.with_discarded.find(attributes[:rate_card_rate_id]) if attributes[:rate_card_rate_id]
    attributes[:rate_override] = RateOverride.with_discarded.where(organization:).find(attributes[:rate_override_id]) if attributes[:rate_override_id]
    attributes[:pricing_unit] = organization.pricing_units.find(attributes[:pricing_unit_id]) if attributes[:pricing_unit_id]

    new(attributes)
  end

  def proration_ratio=(value)
    @proration_ratio = PRORATION_RATIO_TYPE.cast(value)
  end

  def initialize(attributes = {})
    values = attributes.to_h.symbolize_keys
    ATTRIBUTES.each do |name|
      instance_variable_set("@#{name}", values[name.to_sym]) if name.end_with?("_id")
    end
    %i[organization customer contract contract_rate_card rate_card_rate rate_override pricing_unit
      rate_properties currency started_at ended_at cycle_started_at billing_at proration_ratio billable_metric_code].each do |attribute|
      public_send("#{attribute}=", values[attribute]) if values.key?(attribute)
    end
  end

  %i[organization customer contract contract_rate_card rate_card_rate rate_override pricing_unit].each do |association|
    define_method("#{association}_id") do
      instance_variable_get("@#{association}_id") || public_send(association)&.id
    end
  end

  def attributes
    ATTRIBUTES.index_with { |name| public_send(name) }
  end

  def rate
    rate_override || rate_card_rate
  end

  def recurring_advance_invoiceable?
    card = contract_rate_card.rate_card
    product = card.product
    metric = product.billable_metric
    card.advance? && product.metered? && card.display_on_invoice? && metric&.recurring?
  end

  def target_key
    "contract-#{contract_id}-#{contract_rate_card.product.target_key}"
  end

  def empty_product_filter
    ProductFilter.new(organization:, product: contract_rate_card.rate_card.product)
  end

  def priced_product_filter_ids
    product = contract_rate_card.rate_card.product
    timezone = customer.applicable_timezone
    date_range = started_at.in_time_zone(timezone).to_date..ended_at.in_time_zone(timezone).to_date
    cache_key = [product.id, date_range]
    @priced_product_filter_ids_cache ||= {}
    @priced_product_filter_ids_cache[cache_key] ||= contract.applied_rate_cards
      .joins(:rate_card)
      .where(effective_date: date_range)
      .where(rate_cards: {product_id: product.id})
      .where.not(rate_cards: {product_filter_id: nil})
      .pluck("rate_cards.product_filter_id")
  end

  def duration_in_days
    exclusive_end = BillingSegment.exclusive_end(ended_at.floor(6))
    Billing::Days.between(started_at, exclusive_end, timezone: customer.applicable_timezone)
  end

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
    rate_override ? rate_override.pricing_unit_conversion_rate : rate_card_rate.applied_pricing_unit_conversion_rate
  end

  def min_amount_cents
    rate_override ? rate_override.min_amount_cents : rate_card_rate.min_amount_cents
  end

  def prorated_min_amount_cents
    minimum = min_amount_cents.to_d * proration_ratio
    if pricing_unit
      minimum / Money::Currency.new(currency).subunit_to_unit /
        pricing_unit_conversion_rate * pricing_unit.subunit_to_unit.to_d
    else
      minimum
    end
  end
end
