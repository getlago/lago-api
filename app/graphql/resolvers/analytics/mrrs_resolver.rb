# frozen_string_literal: true

module Resolvers
  module Analytics
    class MrrsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization
      include BillingEntityArgsResolvable

      REQUIRED_PERMISSION = "analytics:view"

      description "Query MRR of an organization"

      argument :billing_entity_code, String, required: false
      argument :currency, Types::CurrencyEnum, required: false

      type Types::Analytics::Mrrs::Object.collection_type, null: false

      def resolve(**args)
        raise unauthorized_error unless License.premium?

        error = resolve_billing_entity!(args)
        return error if error

        ::Analytics::Mrr.find_all_by(current_organization.id, **args.merge({months: 12}))
      end
    end
  end
end
