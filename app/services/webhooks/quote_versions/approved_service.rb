# frozen_string_literal: true

module Webhooks
  module QuoteVersions
    class ApprovedService < Webhooks::BaseService
      include OrderForms::Premium

      def call
        return unless order_forms_enabled?(object.organization)
        super
      end

      private

      def object_serializer
        ::V1::QuoteVersionSerializer.new(
          object,
          root_name: "quote_version"
        )
      end

      def webhook_type
        "quote_version.approved"
      end

      def object_type
        "quote_version"
      end
    end
  end
end
