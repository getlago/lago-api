# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Events
  module Stores
    module Utils
      module QueryHelpers
        def with_ctes(ctes, query)
          <<-SQL
            WITH #{ctes.map { |name, sql| "#{name} AS (#{sql})" }.join(",\n")}

            #{query}
          SQL
        end
      end
    end
  end
end
