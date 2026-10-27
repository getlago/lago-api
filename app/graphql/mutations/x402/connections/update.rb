# frozen_string_literal: true

module Mutations
  module X402
    module Connections
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateX402Connection"
        description "Updates an x402 connection"

        input_object_class Types::X402::UpdateConnectionInput
        type Types::X402::Connection

        def resolve(id:, **args)
          raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

          connection = current_organization.x402_connections.find_by(id:)
          result = ::X402::Connections::UpdateService.call(connection:, params: params(args))

          result.success? ? result.connection : result_error(result)
        end

        private

        def params(args)
          args[:payout_addresses] = args[:payout_addresses].to_h.compact if args.key?(:payout_addresses)

          args.reject { |key, value| key.to_s.start_with?("cdp_api_key") && Types::ObfuscatedStringType.obfuscated?(value) }
        end
      end
    end
  end
end
