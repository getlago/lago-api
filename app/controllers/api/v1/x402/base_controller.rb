# frozen_string_literal: true

module Api
  module V1
    module X402
      class BaseController < Api::V1::BaseController
        include PremiumFeatureOnly

        before_action :ensure_x402_payments_enabled

        private

        def ensure_x402_payments_enabled
          forbidden_error(code: "feature_unavailable") unless current_organization.feature_flag_enabled?(:x402_payments)
        end

        def raw_body_section(root)
          body = JSON.parse(request.raw_post)
          section = body[root] if body.is_a?(Hash)
          section if section.is_a?(Hash)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
