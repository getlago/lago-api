# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OrderTypeService < BaseValidator
      NESTED_ITEM_KEYS = %w[payload overrides].freeze

      def initialize(result, quote_version:, scope: :approve)
        @quote_version = quote_version
        @scope = scope.to_sym
        super(result)
      end

      def valid?
        validate_structure

        # Business validations assume a well-shaped document: fail fast on structural errors.
        if errors.empty?
          validate_billing_items
        end

        return true unless errors?

        result.validation_failure!(errors:)
        false
      end

      private

      attr_reader :quote_version, :scope

      def schema
        raise NotImplementedError
      end

      def allowed_billing_item_keys
        []
      end

      def approve?
        scope == :approve
      end

      def validate_billing_items
        # Override in concrete order type validators.
      end

      def validate_structure
        entries = SchemaErrorMapper.new(document: schema_document).call(schema.validate(schema_document))
        entries.each { |field, error_code| add_error(field:, error_code:) }

        normalize_currency
      end

      def normalize_currency
        currency = quote_version.currency
        if currency.present? && errors[:currency].blank?
          quote_version.currency = currency.to_s.upcase
        end
      end

      def schema_document
        @schema_document ||= {
          "currency" => quote_version.currency.presence&.to_s&.upcase,
          "billing_items" => normalized_billing_items
        }
      end

      def normalized_billing_items
        raw = quote_version.billing_items
        return {} if raw.nil?
        return raw unless raw.is_a?(Hash)

        normalized = raw.deep_stringify_keys
        allowed_billing_item_keys.map(&:to_s).each do |key|
          next unless normalized.key?(key)

          normalized[key] = normalize_collection(normalized[key])
        end
        normalized
      end

      def normalize_collection(items)
        return [] if items.nil?
        return items unless items.is_a?(Array)

        items.each do |item|
          next unless item.is_a?(Hash)

          NESTED_ITEM_KEYS.each do |key|
            item[key] = {} if item[key].nil?
          end
        end
        items
      end

      # Business validations read the schema-validated document: string keys,
      # collections are arrays of hashes, nested payload/overrides are hashes.
      def billing_item_array(key)
        schema_document["billing_items"].fetch(key, [])
      end

      def billing_item_field(collection_key, item, index, attribute)
        ref = item["local_id"].presence || index
        :"#{collection_key}/#{ref}/#{attribute}"
      end
    end
  end
end
