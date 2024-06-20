# frozen_string_literal: true

module Resolvers
  module Integrations
    class AccountsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:view'

      description 'Query integration accounts'

      argument :integration_id, ID, required: false

      type Types::Integrations::Accounts::Object.collection_type, null: true

      def resolve(integration_id: nil)
        integration = current_organization.integrations.find(integration_id)

        result = ::Integrations::Aggregator::AccountsService.call(integration:)

        result.accounts
      end
    end
  end
end
