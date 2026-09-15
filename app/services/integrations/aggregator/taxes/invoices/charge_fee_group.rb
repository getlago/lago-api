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
            ChargeGroup.key(charge_id)
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
            allocations = group_taxes.tax_breakdown.map { |tax| allocate(tax.tax_amount) }

            fees.map.with_index do |fee, index|
              breakdown = shared_breakdown(group_taxes, fee, allocations, index)

              TaxResult.new(
                item_key: fee.item_key,
                item_id: fee.id || fee.item_id,
                item_code: group_taxes.item_code,
                amount_cents: fee.sub_total_excluding_taxes_amount_cents,
                tax_amount_cents: breakdown.sum(&:allocated_amount_cents),
                tax_breakdown: breakdown,
                group_key: item_key,
                group_tax_amount_cents: group_taxes.tax_amount_cents
              )
            end
          end

          private

          def shared_breakdown(group_taxes, fee, allocations, index)
            share = share_of(fee.sub_total_excluding_taxes_amount_cents)

            group_taxes.tax_breakdown.map.with_index do |tax, tax_index|
              shared_breakdown_item(tax, share, allocations[tax_index][index])
            end
          end

          # NOTE: Fees::ApplyProviderTaxesService derives the taxable base rate from the ratio of
          #       the returned tax amount to the rate applied to the fee sub-total. Scaling the
          #       amount down to the fee's share of the group keeps that ratio the group's ratio.
          def shared_breakdown_item(tax, share, allocated_amount_cents)
            TaxResult::TaxBreakdownItem.new(
              name: tax.name,
              rate: tax.rate,
              tax_amount: tax.tax_amount * share,
              type: tax.type,
              allocated_amount_cents:
            )
          end

          # NOTE: Rounding each fee's share on its own accumulates up to half a cent per fee and
          #       per jurisdiction against the single figure the provider priced the charge at.
          #       A largest-remainder pass keeps the whole-group amount exact instead.
          def allocate(total)
            return Array.new(fees.size, 0) if total.nil? || total.zero? || sub_total_excluding_taxes_amount_cents.zero?

            exact = fees.map { |fee| total.to_d * share_of(fee.sub_total_excluding_taxes_amount_cents) }
            allocated = exact.map(&:truncate)
            residue = total.round - allocated.sum
            step = residue.negative? ? -1 : 1

            exact.each_with_index
              .sort_by { |value, index| [-(value - value.truncate) * step, index] }
              .first(residue.abs)
              .each { |_value, index| allocated[index] += step }

            allocated
          end

          def share_of(amount_cents)
            if sub_total_excluding_taxes_amount_cents.zero?
              0.to_d
            else
              amount_cents.to_d / sub_total_excluding_taxes_amount_cents
            end
          end
        end
      end
    end
  end
end
