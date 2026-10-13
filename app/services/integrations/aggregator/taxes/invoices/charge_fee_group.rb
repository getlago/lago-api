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
              .flat_map { |charge_fees| charge_fees.one? ? charge_fees : new(fees: charge_fees) }
          end

          def initialize(fees:)
            @fees = fees
          end

          attr_reader :fees

          delegate :charge_id, :billable_metric, to: "fees.first"

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
            fees.zip(fee_tax_breakdowns(group_taxes)).map do |fee, breakdown|
              TaxResult.new(
                item_key: fee.item_key,
                item_id: fee.id || fee.item_id,
                item_code: group_taxes.item_code,
                amount_cents: fee.sub_total_excluding_taxes_amount_cents,
                tax_amount_cents: breakdown.sum(&:allocated_amount_cents),
                tax_breakdown: breakdown
              )
            end
          end

          private

          def fee_tax_breakdowns(group_taxes)
            breakdowns = Array.new(fees.size) { [] }
            group_taxes.tax_breakdown.zip(group_taxes.allocated_amounts).each do |tax, amount|
              precise_shares = Allocation.precise(tax.tax_amount, fee_weights)
              booked_shares = Allocation.call(amount, fee_weights)

              breakdowns.zip(precise_shares, booked_shares).each do |breakdown, precise, booked|
                breakdown << tax.with(tax_amount: precise, allocated_amount_cents: booked)
              end
            end

            breakdowns
          end

          def fee_weights
            @fee_weights ||= fees.map(&:sub_total_excluding_taxes_amount_cents)
          end
        end
      end
    end
  end
end
