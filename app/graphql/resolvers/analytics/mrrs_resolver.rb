# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Resolvers
  module Analytics
    class MrrsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "analytics:view"

      description "Query MRR of an organization"

      argument :billing_entity_id, ID, required: false
      argument :currency, Types::CurrencyEnum, required: false

      type Types::Analytics::Mrrs::Object.collection_type, null: false

      def resolve(**args)
        raise unauthorized_error unless License.premium?

        ::Analytics::Mrr.find_all_by(current_organization.id, **args.merge({months: 12}))
      end
    end
  end
end
