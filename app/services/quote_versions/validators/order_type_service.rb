# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OrderTypeService < BaseValidator
      def initialize(result, quote_version:, scope: :approve)
        @quote_version = quote_version
        @scope = scope.to_sym
        super(result)
      end

      def valid?
        validate_currency_format
        validate_billing_items_shape
        validate_billing_items
        validate_completeness if approve?

        return true unless errors?

        result.validation_failure!(errors:)
        false
      end

      private

      attr_reader :quote_version, :scope

      def allowed_billing_item_keys
        []
      end

      def approve?
        scope == :approve
      end

      def update?
        scope == :update
      end

      def validate_billing_items
        # Override in concrete order type validators.
      end

      def validate_completeness
        # Override in concrete order type validators when approve needs required fields.
      end

      def billing_items
        @billing_items ||= if raw_billing_items.is_a?(Hash)
          raw_billing_items.with_indifferent_access
        else
          {}.with_indifferent_access
        end
      end

      def billing_item_array(key)
        items = billing_items[key]
        items.is_a?(Array) ? items : []
      end

      def validate_collection_shape(key)
        items = billing_items[key]
        return if items.nil?
        return if items.is_a?(Array) && items.all? { |item| item.is_a?(Hash) }

        add_billing_items_error
      end

      def validate_nested_hash(item, index, collection_key:, nested_key:)
        return unless item.key?(nested_key)

        value = item[nested_key]
        return if value.nil? || value.is_a?(Hash)

        add_error(field: billing_item_field(collection_key, item, index, nested_key), error_code: "value_is_invalid")
      end

      def safe_hash(value)
        value.is_a?(Hash) ? value.with_indifferent_access : {}.with_indifferent_access
      end

      def billing_item_field(collection_key, item, index, attribute)
        ref = item[:local_id].presence || index
        :"#{collection_key}/#{ref}/#{attribute}"
      end

      def add_billing_items_error(error_code: "value_is_invalid")
        errors[:billing_items] ||= []
        return if errors[:billing_items].include?(error_code)

        add_error(field: :billing_items, error_code:)
      end

      def validate_currency_format
        currency = quote_version.currency
        return if currency.blank?
        return if Currencies::ACCEPTED_CURRENCIES.key?(currency.to_sym)

        add_error(field: :currency, error_code: "value_is_invalid")
      end

      def raw_billing_items
        @raw_billing_items ||= quote_version.billing_items
      end

      def validate_billing_items_shape
        raw = raw_billing_items
        return if raw.nil?

        unless raw.is_a?(Hash)
          add_billing_items_error
          return
        end

        validate_allowed_billing_item_keys(raw)
      end

      def validate_allowed_billing_item_keys(raw)
        unexpected_keys = raw.keys.map(&:to_s) - allowed_billing_item_keys.map(&:to_s)
        return if unexpected_keys.empty?

        add_billing_items_error
      end
    end
  end
end
