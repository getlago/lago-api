# frozen_string_literal: true

module Resolvers
  module Analytics
    class InvoicedUsagesResolver < GraphQL::Schema::Resolver
      include AuthenticableApiUser
      include RequiredOrganization

      description "Query invoiced usage of an organization"

      argument :currency, Types::CurrencyEnum, required: false

      type Types::Analytics::InvoicedUsages::Object.collection_type, null: false

      def resolve(**args)
        validate_organization!

        raise unauthorized_error unless License.premium?

        ::Analytics::InvoicedUsage.find_all_by(current_organization.id, **args.merge({months: 12}))
      end
    end
  end
end
