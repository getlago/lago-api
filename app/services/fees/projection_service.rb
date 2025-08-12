# frozen_string_literal: true

module Fees
  class ProjectionService < ::BaseService
    Result = BaseResult[:projected_amount_cents, :projected_units, :projected_pricing_unit_amount_cents]

    def initialize(fees:)
      @fees = fees
      @first_fee = fees.first

      @charge = @first_fee&.charge
      @subscription = @first_fee&.subscription
      @charge_filter = @first_fee&.charge_filter
      @from_datetime = @first_fee&.properties&.dig("from_datetime")
      @to_datetime = @first_fee&.properties&.dig("to_datetime")
      @charges_duration_in_days = @first_fee&.properties&.dig("charges_duration")
      @currency = @subscription&.plan&.amount&.currency
      @properties_for_charge_model = @charge_filter&.properties || @charge&.properties

      super(nil)
    end

    def call
      result = Result.new

      if charge&.billable_metric&.recurring?
        current_amount_cents = fees.sum(&:amount_cents)
        current_units = fees.sum { |f| BigDecimal(f.units) }
        current_pricing_unit_amount_cents = fees.sum { |f| f.pricing_unit_usage&.amount_cents || 0 }
        current_pricing_unit_amount_cents = nil if current_pricing_unit_amount_cents.zero?

        result.projected_amount_cents = current_amount_cents
        result.projected_units = current_units
        result.projected_pricing_unit_amount_cents = current_pricing_unit_amount_cents
        return result
      end

      if fees.blank? || !(period_ratio > 0 && period_ratio < 1)
        result.projected_amount_cents = BigDecimal("0")
        result.projected_units = BigDecimal("0")
        result.projected_pricing_unit_amount_cents = BigDecimal("0")
        return result
      end

      aggregation_result = run_aggregation
      return result.fail_with_error!(aggregation_result.error) unless aggregation_result.success?

      charge_model_result = Charges::ChargeModelFactory.new_instance(
        charge: charge,
        aggregation_result: aggregation_result,
        properties: properties_for_charge_model,
        period_ratio: period_ratio,
        calculate_projected_usage: true
      ).apply

      return result.fail_with_error!(charge_model_result.error) unless charge_model_result.success?

      if charge_model_result.try(:grouped_results)
        target_group_result = charge_model_result.grouped_results.find do |group_result|
          group_result.grouped_by == first_fee.grouped_by
        end
        charge_model_result = target_group_result if target_group_result
      end

      result.projected_amount_cents = calculate_projected_amount_cents(charge_model_result)
      result.projected_units = charge_model_result.projected_units
      result.projected_pricing_unit_amount_cents = calculate_projected_pricing_unit_amount_cents(charge_model_result)
      result
    end

    private

    attr_reader :fees, :first_fee, :charge, :subscription, :charge_filter,
      :from_datetime, :to_datetime, :charges_duration_in_days,
      :currency, :properties_for_charge_model

    def period_ratio
      return @period_ratio if defined?(@period_ratio)

      from_date = from_datetime.to_date
      to_date = to_datetime.to_date
      current_date = Time.current.to_date

      total_days = (to_date - from_date).to_i + 1

      return @period_ratio = 1.0 if current_date >= to_date
      return @period_ratio = 0.0 if current_date < from_date

      days_passed = (current_date - from_date).to_i + 1

      ratio = days_passed.fdiv(total_days)
      @period_ratio = ratio.clamp(0.0, 1.0)
    end

    def run_aggregation
      boundaries = {
        from_datetime: from_datetime.to_date,
        to_datetime: to_datetime.to_date,
        charges_duration: charges_duration_in_days
      }

      aggregator = BillableMetrics::AggregationFactory.new_instance(
        charge: charge,
        subscription: subscription,
        boundaries: boundaries,
        filters: aggregation_filters,
        current_usage: true
      )

      aggregator.aggregate(options: {is_current_usage: true})
    end

    def aggregation_filters
      local_charge_filter = charge_filter

      if local_charge_filter.nil? && charge.filters.any?
        local_charge_filter = ChargeFilter.new(charge: charge)
      end

      filters = {}
      model = local_charge_filter.presence || charge
      filters[:grouped_by] = model.pricing_group_keys if model.pricing_group_keys.present?

      if local_charge_filter.present?
        result = ChargeFilters::MatchingAndIgnoredService.call(charge: charge, filter: local_charge_filter)
        filters[:charge_filter] = local_charge_filter
        filters[:matching_filters] = result.matching_filters
        filters[:ignored_filters] = result.ignored_filters
      end

      filters
    end

    def calculate_projected_amount_cents(amount_result)
      return 0 unless amount_result.projected_amount

      rounded_projected_amount = amount_result.projected_amount.round(currency.exponent)
      rounded_projected_amount * currency.subunit_to_unit
    end

    def calculate_projected_pricing_unit_amount_cents(amount_result)
      return nil unless charge.applied_pricing_unit
      return nil unless amount_result.projected_amount

      projected_pricing_unit_usage = PricingUnitUsage.build_from_fiat_amounts(
        amount: amount_result.projected_amount,
        unit_amount: amount_result.unit_amount,
        applied_pricing_unit: charge.applied_pricing_unit
      )
      projected_pricing_unit_usage.to_fiat_currency_cents(currency)[:amount_cents]
    end
  end
end
