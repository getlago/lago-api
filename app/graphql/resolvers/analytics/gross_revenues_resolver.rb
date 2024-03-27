# frozen_string_literal: true

module Resolvers
  module Analytics
    class GrossRevenuesResolver < GraphQL::Schema::Resolver
      include AuthenticableApiUser
      include RequiredOrganization

      description "Query gross revenue of an organization"

      argument :currency, Types::CurrencyEnum, required: false
      argument :external_customer_id, String, required: false

      type Types::Analytics::GrossRevenues::Object.collection_type, null: false

      def resolve(**args)
        validate_organization!

        ::Analytics::GrossRevenue.find_all_by(current_organization.id, **args.merge(months: 12))
      end
    end
  end
end
