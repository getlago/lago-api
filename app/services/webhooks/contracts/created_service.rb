# frozen_string_literal: true

module Webhooks
  module Contracts
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ContractSerializer.new(object, root_name: "contract", webhook: true)
      end

      def webhook_type
        "contract.created"
      end

      def object_type
        "contract"
      end
    end
  end
end
