# frozen_string_literal: true

module Webhooks
  module Contracts
    class CanceledService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ContractSerializer.new(object, root_name: "contract")
      end

      def webhook_type
        "contract.canceled"
      end

      def object_type
        "contract"
      end
    end
  end
end
