# frozen_string_literal: true

# Lays out the fees of a catalog invoice the way a v1 receipt lays out the fees of its
# subscriptions: per contract, then per billing period.
class ProductCatalogReceiptHelper
  Period = Data.define(:from_datetime, :to_datetime, :fees)

  # The rate models with a v1 detail partial; the others render as a single line.
  DETAILED_RATE_MODELS = %w[graduated graduated_percentage percentage volume package].freeze

  def self.contracts(invoice)
    fees = invoice.fees.product
      .includes(:product_filter, :pricing_unit_usage, :rate_card_rate, :rate_override, :applied_taxes, invoiceable: :billable_metric, contract_rate_card: :rate_card, true_up_parent_fee: :invoiceable, contract: :catalog_plan)
      .to_a

    fees.group_by(&:contract).sort_by { |contract, _| ProductCatalogInvoiceHelper.contract_name(contract).to_s.downcase }
  end

  # Fixed products first, then metered ones, each sorted by title, and every true-up right
  # after the fee it tops up, in the billing period of that fee.
  def self.periods(fees)
    true_ups, billed = fees.partition(&:true_up_parent_fee_id)

    billed.group_by { it.properties.values_at("from_datetime", "to_datetime") }.sort_by { |(from, _), _| from.to_s }.map do |(from, to), period_fees|
      ordered = period_fees.sort_by { [it.invoiceable.fixed? ? 0 : 1, FeeDisplayHelper.fee_title(it).downcase] }
      Period.new(
        from_datetime: from.presence && Time.zone.parse(from),
        to_datetime: to.presence && Time.zone.parse(to),
        fees: ordered.flat_map { |fee| [fee, *true_ups.select { it.true_up_parent_fee_id == fee.id }] }
      )
    end
  end

  def self.detailed?(fee)
    !fee.amount.zero? && fee.amount_details.present? && DETAILED_RATE_MODELS.include?(fee.rate_model)
  end

  def self.percentage?(fee)
    %w[percentage graduated_percentage].include?(fee.rate_model)
  end

  # The fees a v1 receipt breaks down day by day (Invoice#recurring_fees): recurring sums and unique
  # counts billed in arrears, per product, for the products that billed units.
  def self.recurring_fees(fees)
    fees
      .select { recurring_breakdown?(it) }
      .sort_by { [it.properties["charges_from_datetime"].to_s, it.filter_display_name.to_s.downcase] }
      .group_by(&:invoiceable_id)
      .values
      .select { |product_fees| product_fees.sum(&:units).positive? }
      .sort_by { |product_fees| product_fees.first.invoice_name.downcase }
  end

  def self.recurring_breakdown(fee)
    BillingSegments::Fees::RecurringBreakdownService.call!(fee:).breakdown
  end

  def self.recurring_breakdown?(fee)
    metric = fee.invoiceable.billable_metric

    !fee.true_up_parent_fee_id? &&
      fee.contract_rate_card.rate_card.arrears? &&
      metric&.recurring? &&
      BillingSegments::Fees::RecurringBreakdownService::BREAKDOWN_SERVICES.key?(metric.aggregation_type)
  end

  def self.contract_total(fees)
    Money.new(fees.sum { it.amount_cents + it.taxes_amount_cents }, fees.first.amount_currency)
  end
end
