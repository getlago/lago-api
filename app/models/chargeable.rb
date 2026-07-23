# frozen_string_literal: true

# Value object carrying the aggregation and pricing parameters shared by the
# legacy Charge path and the product-catalog billing engine.
#
# It exposes the minimal interface consumed by BillableMetrics::AggregationFactory
# and ChargeModels::Factory so neither subsystem depends on the concrete Charge model.
# The legacy path builds it from a Charge via .from_charge; the billing engine builds
# it directly from a rate card rate and a subscription product item.
Chargeable = Data.define(
  :id,
  :billable_metric,
  :charge_model,
  :properties,
  :pay_in_advance,
  :prorated,
  :plan,
  :accepts_target_wallet
) do
  def self.from_charge(charge)
    new(
      id: charge.id,
      billable_metric: charge.billable_metric,
      charge_model: charge.charge_model,
      properties: charge.properties,
      pay_in_advance: charge.pay_in_advance?,
      prorated: charge.prorated?,
      plan: charge.plan,
      accepts_target_wallet: charge.accepts_target_wallet
    )
  end

  def initialize(charge_model:, id: nil, billable_metric: nil, properties: {}, pay_in_advance: false, prorated: false, plan: nil, accepts_target_wallet: false)
    super
  end

  def pay_in_advance?
    pay_in_advance
  end

  def prorated?
    prorated
  end

  def dynamic?
    charge_model.to_s == "dynamic"
  end
end
