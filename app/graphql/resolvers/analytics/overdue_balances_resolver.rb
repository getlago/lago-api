# frozen_string_literal: true

module Resolvers
  module Analytics
    class OverdueBalancesResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'analytics:view'

      description 'Query overdue balances of an organization'

      argument :currency, Types::CurrencyEnum, required: false
      argument :external_customer_id, String, required: false
      argument :months, Integer, required: false

      type Types::Analytics::OverdueBalances::Object.collection_type, null: false

      def resolve(**args)
        ::Analytics::OverdueBalance.find_all_by(current_organization.id, **args)
      end
    end
  end
end
