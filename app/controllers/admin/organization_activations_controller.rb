# frozen_string_literal: true

module Admin
  # The one admin route drawn in production: billing-accounts opens a self-serve production organization once the
  # customer saved a card. It takes its own key, never ADMIN_API_KEY, and is served on the internal ingress only.
  class OrganizationActivationsController < BaseController
    def create
      organization = Organization.find_by(id: params[:id])
      return not_found_error(resource: "organization") unless organization

      result = ::Organizations::ActivateService.call(organization:)
      return render_error_response(result) unless result.success?

      render(json: {organization: result.organization.slice(:id, :activation_status)})
    end

    private

    def authenticate
      # The scheme is case-insensitive (RFC 7235), and spacing around the token is not significant.
      token = request.headers["Authorization"].to_s[/\Abearer\s+(\S+)\s*\z/i, 1]
      expected = Lago::SelfServe.billing_accounts_key

      if token.present? && expected.present? && same_key?(token, expected)
        CurrentContext.email = nil
        true
      else
        unauthorized_error
      end
    end

    # Constant time, whatever the lengths.
    def same_key?(token, expected)
      ActiveSupport::SecurityUtils.fixed_length_secure_compare(
        OpenSSL::Digest::SHA256.digest(token), OpenSSL::Digest::SHA256.digest(expected)
      )
    end
  end
end
