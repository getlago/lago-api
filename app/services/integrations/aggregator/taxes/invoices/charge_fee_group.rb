# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        # Quacks like a Fee so the provider payloads need no notion of grouping.
        class ChargeFeeGroup
          def self.build(fees)
            ChargeGroup
              .by_charge(fees) { |fee| fee.charge_id if fee.charge? }
              .flat_map { |charge_fees| charge_fees.one? ? charge_fees : new(charge_id: charge_fees.first.charge_id, fees: charge_fees) }
          end

          def initialize(charge_id:, fees:)
            @charge_id = charge_id
            @fees = fees
          end

          attr_reader :charge_id, :fees

          def id
            nil
          end

          def item_key
            charge_id
          end
          alias_method :item_id, :item_key

          def charge?
            true
          end

          def billable_metric
            fees.first.billable_metric
          end

          def units
            fees.sum(&:units)
          end

          def amount_cents
            fees.sum(&:amount_cents)
          end

          def sub_total_excluding_taxes_amount_cents
            @sub_total_excluding_taxes_amount_cents ||= fees.sum(&:sub_total_excluding_taxes_amount_cents)
          end

          def split_taxes(group_taxes)
            allocations = group_taxes.tax_breakdown.map { |tax| Allocation.call(tax.tax_amount, fee_weights) }

            fees.map.with_index do |fee, index|
              breakdown = shared_breakdown(group_taxes, allocations, index)

              TaxResult.new(
                item_key: fee.item_key,
                item_id: fee.id || fee.item_id,
                item_code: group_taxes.item_code,
                amount_cents: fee.sub_total_excluding_taxes_amount_cents,
                tax_amount_cents: breakdown.sum(&:tax_amount),
                tax_breakdown: breakdown,
                charge_id:
              )
            end
          end

          private

          def shared_breakdown(group_taxes, allocations, index)
            group_taxes.tax_breakdown.map.with_index do |tax, tax_index|
              shared_breakdown_item(tax, allocations[tax_index][index])
            end
          end

          def shared_breakdown_item(tax, allocated_amount_cents)
            TaxResult::TaxBreakdownItem.new(
              name: tax.name,
              rate: tax.rate,
              tax_amount: allocated_amount_cents,
              type: tax.type
            )
          end

          def fee_weights
            @fee_weights ||= fees.map(&:sub_total_excluding_taxes_amount_cents)
          end
        end
      end
    end
  end
end
