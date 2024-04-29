# frozen_string_literal: true

module Resolvers
  module Analytics
    class GrossRevenuesResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'analytics:view'

      description 'Query gross revenue of an organization'

      argument :currency, Types::CurrencyEnum, required: false
      argument :external_customer_id, String, required: false

      type Types::Analytics::GrossRevenues::Object.collection_type, null: false

      def resolve(**args)
        ::Analytics::GrossRevenue.find_all_by(current_organization.id, **args.merge(months: 12))
      end
    end
  end
end
