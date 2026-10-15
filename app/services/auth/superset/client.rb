# frozen_string_literal: true

module Auth
  module Superset
    # Shared plumbing for talking to the Superset API: configuration checks,
    # admin authentication, CSRF handling and header builders. Included by the
    # services that need to reach Superset (dashboards listing and guest token
    # minting), so the multi-step auth flow lives in one place.
    module Client
      private

      def http_client
        @http_client ||= LagoHttpClient::SessionClient.new(superset_base_url)
      end

      def base_headers(referer_path: "/")
        {
          "Origin" => superset_base_url,
          "Referer" => "#{superset_base_url}#{referer_path}"
        }
      end

      def api_headers(referer_path: "/")
        base_headers(referer_path:).merge("Accept" => "application/json")
      end

      def authenticated_api_headers(referer_path: "/")
        api_headers(referer_path:).merge(
          "Authorization" => "Bearer #{access_token}",
          "X-CSRFToken" => csrf_token
        )
      end

      def authenticated_json_headers(referer_path: "/")
        authenticated_api_headers(referer_path:).merge("Content-Type" => "application/json")
      end

      def authenticate_with_api
        body = {
          username: superset_username,
          password: superset_password,
          provider: "db"
        }

        headers = api_headers(referer_path: "/login/").merge("Content-Type" => "application/json")
        response = http_client.post("/api/v1/security/login", body:, headers:)
        parsed_response = JSON.parse(response.body)
        access_token = parsed_response["access_token"]

        unless access_token
          result.service_failure!(code: "superset_auth_failed", message: "No access token received from Superset")
          return {success: false}
        end

        {success: true, access_token:}
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: "superset_auth_failed", message: "Failed to authenticate with Superset: #{e.error_code} #{e.message}")
        {success: false}
      end

      def get_csrf_token
        headers = api_headers.merge("Authorization" => "Bearer #{access_token}")
        response = http_client.get("/api/v1/security/csrf_token/", headers:)
        parsed_response = JSON.parse(response.body)
        csrf_token = parsed_response["result"]

        unless csrf_token
          result.service_failure!(code: "superset_no_csrf_token", message: "No CSRF token received from Superset")
          return {success: false}
        end

        {success: true, csrf_token:}
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: "superset_csrf_failed", message: "Failed to get CSRF token: #{e.error_body}")
        {success: false}
      end

      def guest_user_info
        user.presence || {
          first_name: organization.name || "Guest",
          last_name: "User",
          username: "guest_#{organization.id}"
        }
      end

      def ensure_superset_configured
        missing_vars = []
        missing_vars << "SUPERSET_URL" if superset_base_url.blank?
        missing_vars << "SUPERSET_USERNAME" if superset_username.blank?
        missing_vars << "SUPERSET_PASSWORD" if superset_password.blank?

        return if missing_vars.empty?

        result.service_failure!(
          code: "superset_missing_configuration",
          message: "Superset configuration is incomplete. Missing: #{missing_vars.join(", ")}"
        )
      end

      def superset_base_url
        ENV["SUPERSET_URL"]
      end

      def superset_username
        ENV["SUPERSET_USERNAME"]
      end

      def superset_password
        ENV["SUPERSET_PASSWORD"]
      end
    end
  end
end
