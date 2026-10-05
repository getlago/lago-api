# frozen_string_literal: true

module Api
  module V1
    module X402
      class BaseController < Api::BaseController
        include PremiumFeatureOnly

        before_action :ensure_x402_payments_enabled

        private

        def ensure_x402_payments_enabled
          forbidden_error(code: "feature_unavailable") unless current_organization.feature_flag_enabled?(:x402_payments)
        end
      end
    end
  end
end
