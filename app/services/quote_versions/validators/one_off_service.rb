# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OneOffService < BaseValidator
      ADD_ONS_KEY = "add_ons"

      def initialize(result, quote_version:, scope: :approve)
        @quote_version = quote_version
        @scope = scope.to_sym
        super(result)
      end

      def valid?
        validate_currency_format
        validate_billing_items_shape
        validate_add_ons
        validate_completeness if scope == :approve

        return true unless errors?

        result.validation_failure!(errors:)
        false
      end

      private

      attr_reader :quote_version, :scope

      def validate_currency_format
        currency = quote_version.currency
        return if currency.blank?
        return if Currencies::ACCEPTED_CURRENCIES.key?(currency.to_sym)

        add_error(field: :currency, error_code: "value_is_invalid")
      end

      def validate_billing_items_shape
        raw = quote_version.billing_items
        return if raw.nil?

        unless raw.is_a?(Hash)
          add_error(field: :billing_items, error_code: "value_is_invalid")
          return
        end

        add_error(field: :billing_items, error_code: "value_is_invalid") unless valid_billing_items_hash?(raw)
      end

      def valid_billing_items_hash?(raw)
        return false if (raw.keys.map(&:to_s) - [ADD_ONS_KEY]).any?

        items = raw.with_indifferent_access[ADD_ONS_KEY]
        items.nil? || (items.is_a?(Array) && items.all? { |item| item.is_a?(Hash) })
      end

      def validate_add_ons
        add_on_array.each_with_index do |item, index|
          next unless item.is_a?(Hash)

          validate_add_on_id(item, index)
          validate_nested_objects(item, index)
          validate_units(item, index)
          validate_unit_amount(item, index)
          validate_dates(item, index)
          validate_tax_codes(item, index)
        end
      end

      def validate_add_on_id(item, index)
        id = item[:id]
        if id.blank?
          add_error(field: add_on_field(item, index, :id), error_code: "value_is_mandatory") if scope == :approve
          return
        end

        return if add_ons_by_id.key?(id.to_s)

        add_error(field: add_on_field(item, index, :id), error_code: "add_on_not_found")
      end

      def validate_nested_objects(item, index)
        if item.key?(:payload) && !item[:payload].nil? && !item[:payload].is_a?(Hash)
          add_error(field: add_on_field(item, index, :payload), error_code: "value_is_invalid")
        end

        if item.key?(:overrides) && !item[:overrides].nil? && !item[:overrides].is_a?(Hash)
          add_error(field: add_on_field(item, index, :overrides), error_code: "value_is_invalid")
        end
      end

      def validate_units(item, index)
        units = payload(item)[:units]
        if units.nil?
          add_error(field: add_on_field(item, index, :units), error_code: "value_is_mandatory") if scope == :approve
          return
        end

        return if units.is_a?(Numeric) && units.positive?

        add_error(field: add_on_field(item, index, :units), error_code: "value_is_invalid")
      end

      def validate_unit_amount(item, index)
        amount = effective_unit_amount_cents(item, add_ons_by_id[item[:id].to_s])
        if amount.nil?
          add_error(field: add_on_field(item, index, :unit_amount_cents), error_code: "value_is_mandatory") if scope == :approve
          return
        end

        return if amount.is_a?(Numeric) && amount >= 0

        add_error(field: add_on_field(item, index, :unit_amount_cents), error_code: "value_is_invalid")
      end

      def validate_dates(item, index)
        from = payload(item)[:from_datetime]
        to = payload(item)[:to_datetime]
        return if from.blank? && to.blank?

        if from.blank? || to.blank?
          missing = from.blank? ? :from_datetime : :to_datetime
          add_error(field: add_on_field(item, index, missing), error_code: "dates_must_be_paired")
          return
        end

        parsed_from = parse_datetime(from)
        parsed_to = parse_datetime(to)
        add_error(field: add_on_field(item, index, :from_datetime), error_code: "value_is_invalid") if parsed_from.nil?
        add_error(field: add_on_field(item, index, :to_datetime), error_code: "value_is_invalid") if parsed_to.nil?
        return if parsed_from.nil? || parsed_to.nil?

        add_error(field: add_on_field(item, index, :to_datetime), error_code: "from_after_to") if parsed_from > parsed_to
      end

      def validate_tax_codes(item, index)
        codes = Array(payload(item)[:tax_codes]).compact
        return if codes.empty?
        return if (codes.uniq - existing_tax_codes).empty?

        add_error(field: add_on_field(item, index, :tax_codes), error_code: "tax_not_found")
      end

      def existing_tax_codes
        @existing_tax_codes ||= quote_version.organization.taxes.where(code: requested_tax_codes).pluck(:code)
      end

      def requested_tax_codes
        add_on_array.flat_map { |item| item.is_a?(Hash) ? Array(payload(item)[:tax_codes]) : [] }.compact.uniq
      end

      def validate_completeness
        add_error(field: :currency, error_code: "value_is_mandatory") if quote_version.currency.blank?
        add_error(field: ADD_ONS_KEY.to_sym, error_code: "add_ons_required") if add_on_items.empty?
      end

      def billing_items
        @billing_items ||= begin
          raw = quote_version.billing_items
          raw.is_a?(Hash) ? raw.with_indifferent_access : {}.with_indifferent_access
        end
      end

      def add_on_array
        @add_on_array ||= begin
          items = billing_items[ADD_ONS_KEY]
          items.is_a?(Array) ? items : []
        end
      end

      def add_on_items
        @add_on_items ||= add_on_array.select { |item| item.is_a?(Hash) }
      end

      def payload(item)
        value = item[:payload]
        value.is_a?(Hash) ? value : {}
      end

      def overrides(item)
        value = item[:overrides]
        value.is_a?(Hash) ? value : {}
      end

      def add_ons_by_id
        @add_ons_by_id ||= begin
          ids = add_on_items.filter_map { |item| item[:id] }.uniq
          if ids.empty?
            {}
          else
            quote_version.organization.add_ons.with_discarded.where(id: ids).index_by { |add_on| add_on.id.to_s }
          end
        end
      end

      def effective_unit_amount_cents(item, add_on)
        override_amount = overrides(item)[:unit_amount_cents]
        return override_amount unless override_amount.nil?

        payload_amount = payload(item)[:unit_amount_cents]
        return payload_amount unless payload_amount.nil?

        add_on&.amount_cents
      end

      def add_on_field(item, index, attribute)
        ref = item[:localId].presence || index
        :"#{ADD_ONS_KEY}/#{ref}/#{attribute}"
      end

      def parse_datetime(value)
        return value if value.respond_to?(:strftime)

        Time.zone.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
