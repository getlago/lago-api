# frozen_string_literal: true

module Auth
  module Superset
    # Mints a single, fresh Superset guest token for one dashboard, scoped to the
    # organization through a row-level-security clause. Used to renew the token
    # while an embedded dashboard stays open (guest tokens are short-lived), so
    # the front end can keep the session alive without a full page reload.
    class GuestTokenService < BaseService
      include Auth::Superset::Client

      Result = BaseResult[:guest_token]

      def initialize(organization:, dashboard_id:, user: nil)
        @organization = organization
        @dashboard_id = dashboard_id
        @user = user
        @access_token = nil
        @csrf_token = nil
        @http_client = nil

        super()
      end

      def call
        ensure_superset_configured
        return result unless result.success?

        auth_result = authenticate_with_api
        return result unless auth_result[:success]

        @access_token = auth_result[:access_token]

        csrf_result = get_csrf_token
        return result unless csrf_result[:success]

        @csrf_token = csrf_result[:csrf_token]

        mint_guest_token
        result
      rescue URI::InvalidURIError => e
        result.service_failure!(code: "superset_invalid_url", message: "Invalid Superset URL: #{e.message}")
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        result.service_failure!(code: "superset_timeout", message: "Superset request timed out: #{e.message}")
      rescue JSON::ParserError => e
        result.service_failure!(code: "superset_invalid_response", message: "Invalid JSON response from Superset: #{e.message}")
      rescue => e
        result.service_failure!(code: "superset_error", message: "Superset operation failed: #{e.message}")
      end

      private

      attr_reader :organization, :dashboard_id, :user, :access_token, :csrf_token

      def mint_guest_token
        body = {
          resources: [{id: dashboard_id.to_s, type: "dashboard"}],
          rls: [
            {
              clause: "organization_id = '#{organization.id}'"
            }
          ],
          user: guest_user_info
        }

        response = http_client.post("/api/v1/security/guest_token/", body:, headers: authenticated_json_headers)
        parsed_response = JSON.parse(response.body)
        guest_token = parsed_response["token"] || parsed_response["result"] || parsed_response["access_token"]

        unless guest_token
          result.service_failure!(code: "superset_guest_token_failed", message: "No guest token received from Superset")
          return
        end

        result.guest_token = guest_token
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: "superset_guest_token_failed", message: "Failed to mint guest token: #{e.error_body}")
      end
    end
  end
end
