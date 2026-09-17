# frozen_string_literal: true

module Webhooks
  module Quotes
    class VoidedService < Webhooks::BaseService
      include Webhooks::OrderFormsGate

      private

      def object_serializer
        ::V1::QuoteWithVersionSerializer.new(object, root_name: "quote")
      end

      def webhook_type
        "quote.voided"
      end

      def object_type
        "quote"
      end
    end
  end
end
