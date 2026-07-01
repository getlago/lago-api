# frozen_string_literal: true

module Lago
  module Meilisearch
    # Builds Meilisearch filter expression strings.
    #
    # Neither meilisearch-rails nor the meilisearch client provide a filter
    # builder — they only forward the `filter:` value to the engine — so these
    # helpers centralize the expression syntax (quoting/escaping, IN lists,
    # comparisons) for reuse across queries.
    #
    # Namespaced under Lago:: to avoid clashing with the gem's top-level
    # `Meilisearch` constant.
    module Filter
      module_function

      def eq(field, value)
        "#{field} = #{literal(value)}"
      end

      def in_list(field, values)
        "#{field} IN [#{Array(values).map { |value| literal(value) }.join(", ")}]"
      end

      def not_in(field, values)
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

      # Renders a value for an equality / IN expression: booleans bare, numerics
      # bare, everything else as a quoted, escaped string.
      def literal(value)
        return value.to_s if value == true || value == false
        return value.to_s if value.is_a?(Numeric)

        %("#{value.to_s.gsub('"', '\\"')}")
      end
    end
  end
end
