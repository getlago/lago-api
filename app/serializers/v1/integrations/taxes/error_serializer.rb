# frozen_string_literal: true

module V1
  module Integrations
    module Taxes
      class ErrorSerializer < ModelSerializer
        def serialize
          {
            tax_provider_code: model.code,
            provider_error: options[:provider_error]
          }
        end
      end
    end
  end
end
