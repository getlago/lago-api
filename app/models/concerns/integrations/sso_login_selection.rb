# frozen_string_literal: true

module Integrations
  # NOTE: Several organizations of the same company can configure an Okta or Entra ID integration
  #       on the same email domain, as long as every one of them points to the same identity
  #       provider tenant (same `sso_issuer`). A login then has to pick one of them.
  module SsoLoginSelection
    extend ActiveSupport::Concern

    class_methods do
      # Picks, in order: the integration of the invite's organization, the integration of an
      # organization the user is already an active member of, the first candidate.
      # `candidates` is ordered by priority (oldest first).
      def pick_for_login(candidates, email:, organization_id: nil)
        return candidates.first if candidates.size <= 1

        if organization_id
          invite_integration = candidates.find { it.organization_id == organization_id }
          return invite_integration if invite_integration
        end

        member_organization_ids = Membership.active.joins(:user).where(users: {email:}).pluck(:organization_id)

        candidates.find { member_organization_ids.include?(it.organization_id) } || candidates.first
      end
    end

    private

    def same_identity_provider?(other)
      sso_issuer.present? && other.sso_issuer == sso_issuer
    end
  end
end
