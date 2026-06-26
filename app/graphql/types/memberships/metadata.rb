# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Memberships
    class Metadata < GraphqlPagination::CollectionMetadataType
      field :admin_count, Integer, null: false

      def admin_count
        context[:current_organization].memberships.active.admins.count
      end
    end
  end
end
