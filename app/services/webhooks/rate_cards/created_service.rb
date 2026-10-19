# frozen_string_literal: true

module Webhooks
  module RateCards
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::RateCardSerializer.new(object, root_name: object_type, includes: %i[active_rate rates taxes])
      end

      def webhook_type
        "rate_card.created"
      end

      def object_type
        "rate_card"
      end
    end
  end
end
