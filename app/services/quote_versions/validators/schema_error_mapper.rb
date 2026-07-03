# frozen_string_literal: true

module QuoteVersions
  module Validators
    # Anchors json_schemer errors to the validator field keys, like
    # :"add_ons/<local_id-or-index>/units". The error codes themselves are
    # declared in the schemas via "x-error" and passed through untouched.
    class SchemaErrorMapper
      BILLING_ITEMS_KEY = "billing_items"

      def initialize(document:)
        @document = document
      end

      def call(schemer_errors)
        entries = schemer_errors.flat_map { |error| map_error(error) }
        suppress_required(dedup_billing_items(entries))
      end

      private

      attr_reader :document

      def map_error(error)
        code = error["error"]
        segments = error["data_pointer"].split("/").drop(1)

        if error["type"] == "required"
          error.dig("details", "missing_keys").map { |key| [required_field(segments, key), code] }
        else
          [[field(error, segments), code]]
        end
      end

      def required_field(segments, key)
        if segments == [BILLING_ITEMS_KEY]
          key.to_sym
        else
          item_field(segments[1], segments[2], key)
        end
      end

      def field(error, segments)
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
          item_field(segments[1], segments[2], segments[3])
        else
          item_field(segments[1], segments[2], segments.last)
        end
      end

      def item_field(collection_key, index, attribute)
        item = document.dig(BILLING_ITEMS_KEY, collection_key, index.to_i)
        ref = (item.is_a?(Hash) && item["local_id"].presence) || index
        :"#{collection_key}/#{ref}/#{attribute}"
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
    end
  end
end
