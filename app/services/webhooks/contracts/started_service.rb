# frozen_string_literal: true

module Webhooks
  module Contracts
    class StartedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ContractSerializer.new(object, root_name: "contract", includes: %i[applied_rate_cards])
      end

      def webhook_type
        "contract.started"
      end

      def object_type
        "contract"
      end
    end
  end
end
