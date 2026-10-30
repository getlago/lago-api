# frozen_string_literal: true

module Webhooks
  module ContractRateCards
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ContractAppliedRateCardSerializer.new(object, root_name: "contract_rate_card", webhook: true)
      end

      def webhook_type
        "contract_rate_card.deleted"
      end

      def object_type
        "contract_rate_card"
      end
    end
  end
end
