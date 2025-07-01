# frozen_string_literal: true

module Charges
  class ComputeAllForecastedUsageAmountsService < BaseService
    def initialize(organization:)
      @organization = organization
      @limit = 1000
      @offset = 0
    end

    def call
      loop do
        usages = forecasted_charges_usages
        break if usages.empty?

        usage_amounts = computed_usage_amounts(usages)

        # We will enqueue a job that processes the whole batch of 1000
        DataApi::UpdateForecastedUsageAmountsJob.perform_later(usage_amounts)

        @offset += limit
      end
    end

    private

    attr_reader :organization, :limit, :offset

    def computed_usage_amounts(usages)
      usages.map do |usage|
        # TODO: we can also change it to a Struct instead of a Hash
        amounts = {id: usage["id"]} # id in the DATA API (Primary Key)

        units_forecast_percentiles.each do |units_forecast_percentile|
          amounts[key.sub("units_", "amount_cents_")] = charge_amount_cents(usage, units_forecast_percentile)
        end

        amounts
      end
    end

    def forecasted_charges_usages
      DataApi::Usages::ForecastedChargesService.call!(
        organization,
        limit:,
        offset:
      ).forecasted_charges_usages
    end

    def charge_amount_cents(usage, units_forecast_percentile)
      subscription = Subscription.find(usage["subscription_id"])
      charge = Charge.find(usage["charge_id"])
      charge_filter = ChargeFilter.find_by(id: usage["charge_filter_id"]) # can be nil
      units = usage[units_forecast_percentile]

      Charges::CalculatePriceService.call!(subscription:, units:, charge:, charge_filter:).charge_amount_cents
    end

    def units_forecast_percentiles
      [
        "units_forecast_10th_percentile",
        "units_forecast_50th_percentile",
        "units_forecast_90th_percentile"
      ]
    end
  end
end
