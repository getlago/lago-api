# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  class BaseUnion < GraphQL::Schema::Union
    extend GraphqlPagination::CollectionType
  end
end
