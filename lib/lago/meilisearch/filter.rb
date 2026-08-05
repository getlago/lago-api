# frozen_string_literal: true

module Lago
  module Meilisearch
    # Builds Meilisearch filter expression strings.
    #
    # Neither meilisearch-rails nor the meilisearch client provide a filter
    # builder — they only forward the `filter:` value to the engine — so these
    # helpers centralize the expression syntax (quoting/escaping, IN lists,
    # comparisons) for reuse across queries.
    module Filter
      extend self

      def eq(field, value)
        "#{field} = #{literal(value)}"
      end

      def in_list(field, values)
        "#{field} IN [#{Array(values).map { |value| literal(value) }.join(", ")}]"
      end

      def not_in_list(field, values)
        "#{field} NOT IN [#{Array(values).map { |value| literal(value) }.join(", ")}]"
      end

      def gt(field, value)
        "#{field} > #{value}"
      end

      def gte(field, value)
        "#{field} >= #{value}"
      end

      def lt(field, value)
        "#{field} < #{value}"
      end

      def lte(field, value)
        "#{field} <= #{value}"
      end

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      private

      # Renders a value for an equality / IN expression: booleans bare, numerics
      # bare, everything else as a quoted, escaped string. Backslashes are
      # escaped before quotes so a value ending in `\` cannot neutralize the
      # closing quote and leak into the rest of the expression.
      def literal(value)
        return value.to_s if value == true || value == false
        return value.to_s if value.is_a?(Numeric)

        %("#{value.to_s.gsub(/["\\]/) { |char| "\\#{char}" }}")
      end
    end
  end
end
