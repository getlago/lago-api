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

      def self.from_billing_segment(billing_segment)
        new(source: Sources::BillingSegment.new(billing_segment:))
      end

      delegate :charge,
        :charge_id,
        :selected_filter,
        :fee_type,
        :invoiceable,
        :billable_metric,
        :organization_id,
        :currency,
        :boundaries,
        :properties,
        :pricing_structure,
        :period_ratio,
        :pricing_group_keys,
        :presentation_group_keys_values,
        :matching_and_ignored_filters,
        :pay_in_advance?,
        :prorated?,
        :invoiceable?,
        :applied_pricing_unit,
        to: :source

      %i[billing_segment charge_filter product_filter contract rate_card_rate rate_override].each do |attribute|
        define_method(attribute) do
          source.public_send(attribute) if source.respond_to?(attribute)
        end
      end

      def dynamic?
        pricing_structure.charge_model == "dynamic"
      end

      def filter_id
        selected_filter&.id
      end

      def aggregation_options(current_usage:)
        {
          free_units_per_events: properties["free_units_per_events"].to_i,
          free_units_per_total_aggregation: BigDecimal(properties["free_units_per_total_aggregation"] || 0),
          is_current_usage: current_usage,
          is_pay_in_advance: pay_in_advance?
        }
      end

      def with_filter(filter, **options)
        self.class.new(source: source.with_filter(filter, **options))
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
