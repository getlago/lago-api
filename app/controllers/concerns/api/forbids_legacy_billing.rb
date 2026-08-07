# frozen_string_literal: true

# Blocks writes to legacy pricing REST endpoints once an organization is on
# the product catalog. Reads stay open so already-billed data remains
# accessible during and after migration.
module Api
  module ForbidsLegacyBilling
    extend ActiveSupport::Concern

    # Checked against action_name instead of a before_action :only option:
    # several host controllers define only a subset of these actions, and
    # Rails raises on missing callback actions (raise_on_missing_callback_actions).
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
