# frozen_string_literal: true

# Blocks legacy pricing writes for product-catalog organizations; reads stay
# open for migration.
module Api
  module ForbidsLegacyBilling
    extend ActiveSupport::Concern

    # Checked against action_name: several hosts define only a subset of these
    # actions and Rails raises on missing callback actions.
    LEGACY_WRITE_ACTIONS = %w[create update destroy].freeze

    included do
      before_action :forbid_legacy_billing!
    end

    private

    def forbid_legacy_billing!
      return unless LEGACY_WRITE_ACTIONS.include?(action_name)

      if current_organization&.product_catalog_enabled?
        forbidden_error(code: "legacy_billing_disabled")
      end
    end
  end
end
