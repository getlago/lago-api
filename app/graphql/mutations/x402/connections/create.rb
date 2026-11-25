# frozen_string_literal: true

module Mutations
  module X402
    module Connections
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "CreateX402Connection"
        description "Creates an x402 connection"

        input_object_class Types::X402::CreateConnectionInput
        type Types::X402::Connection

        def resolve(**args)
          raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

          args[:payout_addresses] = args[:payout_addresses].to_h.compact
          result = ::X402::Connections::CreateService.call(organization: current_organization, params: args)

          result.success? ? result.connection : result_error(result)
        end
      end
    end
  end
end
