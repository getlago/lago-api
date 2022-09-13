# frozen_string_literal: true

module Fees
  class ChargeService < BaseService
    def initialize(invoice:, charge:, subscription:, boundaries:)
      @invoice = invoice
      @charge = charge
      @subscription = subscription
      @boundaries = OpenStruct.new(boundaries)
      super(nil)
    end

    def create
      return result if already_billed?

      init_fee
      return result unless result.success?

      result.fee.save!
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def current_usage
      init_fee
    end

    private

    attr_accessor :invoice, :charge, :subscription, :boundaries

    delegate :customer, to: :invoice
    delegate :billable_metric, to: :charge
    delegate :plan, to: :subscription

    def init_fee
      amount_result = compute_amount
      return result.fail!(code: amount_result.error_code, message: amount_result.error) unless amount_result.success?

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      currency = invoice.amount.currency
      rounded_amount = amount_result.amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        charge: charge,
        amount_cents: amount_cents,
        amount_currency: currency,
        vat_rate: customer.applicable_vat_rate,
        fee_type: :charge,
        invoiceable_type: 'Charge',
        invoiceable: charge,
        units: amount_result.units,
        properties: boundaries.to_h,
        events_count: amount_result.count,
      )

      new_fee.compute_vat
      result.fee = new_fee
      result
    end

    def compute_amount
      aggregation_result = aggregator.aggregate(
        from_date: boundaries.charges_from_date,
        to_date: boundaries.charges_to_date,
        options: options,
      )
      return aggregation_result unless aggregation_result.success?

      apply_charge_model_service(aggregation_result)
    end

    def options
      return {} unless charge.properties.is_a?(Hash)

      {
        free_units_per_events: charge.properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(charge.properties['free_units_per_total_aggregation'] || 0),
      }
    end

    def already_billed?
      existing_fee = invoice.fees.find_by(charge_id: charge.id, subscription_id: subscription.id)
      return false unless existing_fee

      result.fee = existing_fee
      true
    end

    def aggregator
      return @aggregator if @aggregator

      aggregator_service = case billable_metric.aggregation_type.to_sym
                           when :count_agg
                             BillableMetrics::Aggregations::CountService
                           when :max_agg
                             BillableMetrics::Aggregations::MaxService
                           when :sum_agg
                             BillableMetrics::Aggregations::SumService
                           when :unique_count_agg
                             BillableMetrics::Aggregations::UniqueCountService
                           when :recurring_count_agg
                             BillableMetrics::Aggregations::RecurringCountService
                           else
                             raise(NotImplementedError)
      end

      @aggregator = aggregator_service.new(billable_metric: billable_metric, subscription: subscription)
    end

    def apply_charge_model_service(aggregation_result)
      return @charge_model if @charge_model

      model_service = case charge.charge_model.to_sym
                      when :standard
                        Charges::ChargeModels::StandardService
                      when :graduated
                        Charges::ChargeModels::GraduatedService
                      when :package
                        Charges::ChargeModels::PackageService
                      when :percentage
                        Charges::ChargeModels::PercentageService
                      when :volume
                        Charges::ChargeModels::VolumeService
                      else
                        raise(NotImplementedError)
      end

      @charge_model = model_service.apply(charge: charge, aggregation_result: aggregation_result)
    end
  end
end
