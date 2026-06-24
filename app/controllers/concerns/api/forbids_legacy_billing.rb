# frozen_string_literal: true

# Blocks writes to legacy pricing REST endpoints once an organization is on
# the product catalog. Reads stay open so already-billed data remains
# accessible during and after migration.
module Api
  module ForbidsLegacyBilling
    extend ActiveSupport::Concern

    included do
      # The write actions live on the host controllers, not this concern.
      before_action :forbid_legacy_billing!, only: %i[create update destroy] # rubocop:disable Rails/LexicallyScopedActionFilter
    end

    private

    def forbid_legacy_billing!
      forbidden_error(code: "legacy_billing_disabled") if current_organization&.product_catalog_enabled?
    end
  end
end
