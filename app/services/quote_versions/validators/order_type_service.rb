# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OrderTypeService < BaseValidator
      BILLING_ITEMS_KEY = "billing_items"
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
        entries = schema.validate(schema_document).flat_map { |error| schema_error_entries(error) }
        entries = suppress_required(dedup_billing_items(entries))
        entries.each { |field, error_code| add_error(field:, error_code:) }

        normalize_currency
      end

      # json_schemer reports errors at JSON pointers, with codes declared in
      # the schemas ("x-error"); anchor each one to a validator field key.
      def schema_error_entries(error)
        code = error["error"]
        segments = error["data_pointer"].split("/").drop(1)

        if error["type"] == "required"
          error.dig("details", "missing_keys").map { |key| [required_error_field(segments, key), code] }
        else
          [[schema_error_field(error, segments), code]]
        end
      end

      def required_error_field(segments, key)
        if segments == [BILLING_ITEMS_KEY]
          key.to_sym
        else
          pointer_item_field(segments[1], segments[2], key)
        end
      end

      def schema_error_field(error, segments)
        case segments.length
        when 1
          segments.first.to_sym
        when 2
          # minItems anchors to the collection; wrong types and unexpected keys
          # roll up to billing_items as a single shape error.
          (error["type"] == "minItems") ? segments.last.to_sym : :billing_items
        when 3
          :billing_items
        when 4
          pointer_item_field(segments[1], segments[2], segments[3])
        else
          pointer_item_field(segments[1], segments[2], segments.last)
        end
      end

      def pointer_item_field(collection_key, index, attribute)
        item = schema_document[BILLING_ITEMS_KEY].dig(collection_key, index.to_i)
        if item.is_a?(Hash)
          billing_item_field(collection_key, item, index, attribute)
        else
          :"#{collection_key}/#{index}/#{attribute}"
        end
      end

      def dedup_billing_items(entries)
        seen = []
        entries.select do |field, code|
          if field != :billing_items
            true
          elsif seen.include?(code)
            false
          else
            seen << code
            true
          end
        end
      end

      def suppress_required(entries)
        if entries.any? { |field, _| field == :billing_items }
          entries.reject { |_, code| code.end_with?("_required") }
        else
          entries
        end
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
