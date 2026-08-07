# frozen_string_literal: true

# Gating for the realtime usage read path (RisingWave-fed
# usage_realtime_projections). Scope is deliberately narrow while the
# pipeline is being proven: count/sum, in arrears, non-prorated,
# non-recurring, no custom expression. Everything else keeps the
# events-store (ClickHouse) aggregation path.
module UsageProjections
  module_function

  def enabled?
    ENV["LAGO_RISINGWAVE_USAGE_ENABLED"] == "true"
  end

  def eligible_charge?(charge)
    return false unless enabled?
    return false if charge.pay_in_advance?
    return false if charge.prorated?

    billable_metric = charge.billable_metric
    return false if billable_metric.recurring?
    return false if billable_metric.expression.present?

    %w[count_agg sum_agg].include?(billable_metric.aggregation_type)
  end
end
