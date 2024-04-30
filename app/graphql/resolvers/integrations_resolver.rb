# frozen_string_literal: true

module Resolvers
  class IntegrationsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'organization:integrations:view'

    description "Query organization's integrations"

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :type, Types::Integrations::IntegrationTypeEnum, required: false

    type Types::Integrations::Object.collection_type, null: true

    def resolve(type: nil, page: nil, limit: nil)
      scope = current_organization.integrations.page(page).per(limit)
      scope = scope.where(type: integration_type(type)) if type.present?
      scope
    end

    private

    def integration_type(type)
      case type
      when 'netsuite'
        'Integrations::NetsuiteIntegration'
      else
        raise(NotImplementedError)
      end
    end
  end
end
