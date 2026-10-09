# frozen_string_literal: true

module V1
  module X402
    class ConnectionSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_organization_id: model.organization_id,
          code: model.code,
          name: model.name,
          facilitator: model.facilitator,
          asset: model.asset,
          networks: model.networks,
          payout_addresses: model.payout_addresses,
          auto_create_customers: model.auto_create_customers,
          created_at: model.created_at.iso8601,
          updated_at: model.updated_at.iso8601
        }
      end
    end
  end
end
