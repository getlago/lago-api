# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ApiKeys
    class SanitizedObject < Object
      graphql_name "SanitizedApiKey"

      def value
        "••••••••" + object.value.last(3)
      end
    end
  end
end
