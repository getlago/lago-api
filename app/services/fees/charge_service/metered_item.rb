# frozen_string_literal: true

module Fees
  class ChargeService
    MeteredItem = Data.define(:source) do
      def self.from_charge(charge:, boundaries:, charge_filter: nil, properties: nil)
        new(
          source: Sources::Charge.new(
            charge:,
            boundaries:,
            charge_filter:,
            properties_override: properties
          )
        )
      end

      delegate :charge,
        :charge_filter,
        :billable_metric,
        :organization_id,
        :currency,
        :boundaries,
        :properties,
        :pricing_structure,
        :period_ratio,
        :pricing_group_keys,
        :presentation_group_keys_values,
        :matching_filters,
        :ignored_filters,
        :matching_and_ignored_filters,
        :aggregation_options,
        :accepts_target_wallet?,
        :pay_in_advance?,
        :prorated?,
        :invoiceable?,
        :applied_pricing_unit,
        to: :source

      def with_charge_filter(charge_filter, properties: nil)
        self.class.new(source: source.with_charge_filter(charge_filter, properties:))
      end

      def filtered_for_charge_boundaries
        properties = boundaries.to_h
        properties["fixed_charges_from_datetime"] = nil
        properties["fixed_charges_to_datetime"] = nil
        properties["fixed_charges_duration"] = nil
        properties
      end
    end
  end
end
