# frozen_string_literal: true

module Webhooks
  module Integrations
    module Taxes
      class ErrorService < Webhooks::BaseService
        private

        def current_organization
          @current_organization ||= object.organization
        end

        def object_serializer
          ::V1::Integrations::Taxes::ErrorSerializer.new(
            object,
            root_name: object_type,
            provider_error: options[:provider_error]
          )
        end

        def webhook_type
          'integration.tax_provider_error'
        end

        def object_type
          'tax_provider_error'
        end
      end
    end
  end
end
