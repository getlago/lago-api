# frozen_string_literal: true

module Fees
  class ReconcileGroupedProviderTaxesService < BaseService
    Result = BaseResult

    def initialize(fees:, provider_taxes:)
      @fees = fees
      @provider_taxes = provider_taxes

      super
    end

    def call
      grouped_taxes.each { |group_taxes| reconcile(group_taxes) }

      result
    end

    private

    attr_reader :fees, :provider_taxes

    def grouped_taxes
      Array(provider_taxes)
        .select { |fee_taxes| fee_taxes.group_key.present? }
        .group_by(&:group_key)
        .values
        .select { |group_taxes| group_taxes.size > 1 }
    end

    def reconcile(group_taxes)
      members = group_taxes.filter_map { |fee_taxes| indexed_fees[fee_taxes.item_key] }
      return unless members.size == group_taxes.size

      delta = group_taxes.first.group_tax_amount_cents - members.sum(&:taxes_amount_cents)

      distribute(delta, absorbers(members, delta))
    end

    def distribute(delta, absorbers)
      step = delta.negative? ? -1 : 1
      remaining = delta.abs

      while remaining.positive?
        absorbed = 0

        absorbers.each do |fee|
          break if remaining.zero?
          next unless absorbable?(fee, step)

          shift_taxes(fee, step)
          remaining -= 1
          absorbed += 1
        end

        break if absorbed.zero?
      end
    end

    def absorbers(members, delta)
      direction = delta.negative? ? 1 : -1

      members
        .select { |fee| absorbing_applied_tax(fee) }
        .sort_by { |fee| [direction * rounding_loss(fee), fee.item_key.to_s] }
    end

    def absorbable?(fee, step)
      if step.negative?
        (absorbing_applied_tax(fee).amount_cents + step) >= 0
      else
        true
      end
    end

    def rounding_loss(fee)
      fee.taxes_precise_amount_cents - fee.taxes_amount_cents
    end

    # NOTE: A zero-rate jurisdiction (exempt, reverse charge) must not carry a tax amount, so
    #       the cent goes to a jurisdiction that actually taxes the fee.
    def absorbing_applied_tax(fee)
      taxable, untaxable = fee.applied_taxes.partition { |tax| tax.tax_rate.positive? }

      (taxable.presence || untaxable).max_by { |tax| [tax.amount_cents, tax.tax_code] }
    end

    # NOTE: The correction stays in the rounded columns: the precise ones hold the exact,
    #       un-rounded taxes and a whole cent does not belong in them.
    def shift_taxes(fee, step)
      applied_tax = absorbing_applied_tax(fee)

      applied_tax.amount_cents += step
      fee.taxes_amount_cents += step

      if fee.persisted?
        applied_tax.save!
        fee.save!
      end
    end

    def indexed_fees
      @indexed_fees ||= fees.index_by(&:item_key)
    end
  end
end
