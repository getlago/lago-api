# frozen_string_literal: true

module BillingEngineMigrations
  module ShadowOutboundGuard
    ERROR_CODE = "shadow_organization_outbound_disabled"

    private

    def shadow_outbound_refused?(organization_id)
      Lookup.shadow_organization?(organization_id)
    end

    def shadow_outbound_failure
      result.forbidden_failure!(code: ERROR_CODE)
    end
  end
end
