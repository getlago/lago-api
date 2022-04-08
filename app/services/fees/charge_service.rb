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

      new_amount_cents = compute_amount

      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        amount_cents: new_amount_cents,
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
      aggregated_events = aggregator.aggregate(from_date: invoice.from_date, to_date: invoice.to_date)
      charge_model.apply(value: aggregated_events)
    end

    def already_billed?
      existing_fee = invoice.fees.where(charge_id: charge.id).first
      return false unless existing_fee

      result.fee = existing_fee
      true
    end

    def aggregator
      aggregator_service = case billable_metric.charge_model.to_sym
                           when :count_agg
                             BillableMetrics::Aggregations::CountService
                           else
                             raise NotImplementedError
      end

      aggregator_service.new(billable_metric: billable_metric, subscription: subscription)
    end

    def charge_model
      model_service = case charge.charge_model.to_sym
                      when :standard
                        Charges::ChargeModels::Standard
                      else
                        raise NotImplementedError
      end

      model_service.new(charge: charge)
    end
  end
end
