# frozen_string_literal: true

module Fees
  class ChargeService < BaseService
    def initialize(invoice:, charge:)
      @invoice = invoice
      @charge = charge
      super(nil)
    end

    def create
      return result if already_billed?

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        charge: charge,
        amount_cents: compute_amount,
        amount_currency: charge.amount_currency,
        vat_rate: charge.vat_rate,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :invoice, :charge

    delegate :plan, :subscription, to: :invoice
    delegate :billable_metric, to: :charge

    def compute_amount
      aggregated_events = aggregator.aggregate(from_date: from_date, to_date: invoice.to_date)
      return result.fail!('aggregation_failure') unless aggregated_events.success?

      amount_result = charge_model.apply(value: aggregated_events.aggregation)
      return result.fail!('charge_model_failure') unless amount_result.success?

      amount_result.amount_cents
    end

    def already_billed?
      existing_fee = invoice.fees.find_by(charge_id: charge.id)
      return false unless existing_fee

      result.fee = existing_fee
      true
    end

    def aggregator
      return @aggregator if @aggregator

      aggregator_service = case billable_metric.aggregation_type.to_sym
                           when :count_agg
                             BillableMetrics::Aggregations::CountService
                           else
                             raise NotImplementedError
      end

      @aggregator = aggregator_service.new(billable_metric: billable_metric, subscription: subscription)
    end

    def charge_model
      return @charge_model if @charge_model

      model_service = case charge.charge_model.to_sym
                      when :standard
                        Charges::ChargeModels::StandardService
                      else
                        raise NotImplementedError
      end

      @charge_model = model_service.new(charge: charge)
    end

    def from_date
      return invoice.from_date unless subscription.previous_subscription

      if subscription.previous_subscription.upgraded?
        date = case plan.interval.to_sym
               when :monthly
                 invoice.from_date.beginning_of_month
               when :yearly
                 invoice.from_date.beginning_of_year
               else
                 raise NotImplementedError
        end

        return date
      end

      invoice.from_date
    end
  end
end
