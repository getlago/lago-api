# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OneOffService < OrderTypeService
      ADD_ONS_KEY = "add_ons"

      private

      def schema
        Schemas::OneOff.for(scope)
      end

      def allowed_billing_item_keys
        [ADD_ONS_KEY]
      end

      def validate_billing_items
        add_on_array.each_with_index do |item, index|
          validate_add_on_id(item, index)
          validate_dates(item, index)
          validate_unit_amount(item, index)
        end
      end

      def validate_add_on_id(item, index)
        id = item["id"]
        if id.blank?
          add_error(field: add_on_field(item, index, :id), error_code: "value_is_mandatory") if approve?
          return
        end

        return if add_ons_by_id.key?(id.to_s)

        add_error(field: add_on_field(item, index, :id), error_code: "add_on_not_found")
      end

      def validate_unit_amount(item, index)
        return if unresolved_add_on_id?(item)

        amount = effective_unit_amount_cents(item, add_ons_by_id[item["id"].to_s])
        if amount.nil?
          add_error(field: add_on_field(item, index, :unit_amount_cents), error_code: "value_is_mandatory") if approve?
          return
        end

        return if amount.is_a?(Numeric) && amount >= 0

        add_error(field: add_on_field(item, index, :unit_amount_cents), error_code: "value_is_invalid")
      end

      def unresolved_add_on_id?(item)
        id = item["id"]
        return false if id.blank?

        !add_ons_by_id.key?(id.to_s)
      end

      def validate_dates(item, index)
        from = payload(item)["from_datetime"]
        to = payload(item)["to_datetime"]
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

      def add_on_array
        @add_on_array ||= billing_item_array(ADD_ONS_KEY)
      end

      def payload(item)
        item["payload"]
      end

      def overrides(item)
        item["overrides"]
      end

      def add_ons_by_id
        @add_ons_by_id ||= begin
          ids = add_on_array.filter_map { |item| item["id"] }.uniq
          if ids.empty?
            {}
          else
            quote_version.organization.add_ons.with_discarded.where(id: ids).index_by { |add_on| add_on.id.to_s }
          end
        end
      end

      def effective_unit_amount_cents(item, add_on)
        override_amount = overrides(item)["unit_amount_cents"]
        return override_amount unless override_amount.nil?

        payload_amount = payload(item)["unit_amount_cents"]
        return payload_amount unless payload_amount.nil?

        add_on&.amount_cents
      end

      def add_on_field(item, index, attribute)
        billing_item_field(ADD_ONS_KEY, item, index, attribute)
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
