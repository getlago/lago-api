# frozen_string_literal: true

module Auth
  class SupersetService < BaseService
    Result = BaseResult[:dashboards]

    def initialize(organization:, user: nil)
      @organization = organization
      @user = user
      @cookies = []
      @csrf_token = nil

      super()
    end

    def call
      # Step 1: Get CSRF token (unauthenticated)
      csrf_result = get_csrf_token
      return result unless csrf_result[:success]

      @csrf_token = csrf_result[:csrf_token]

      # Step 2: Login via HTML form to create session
      login_result = login_to_superset
      return result unless login_result[:success]

      # Step 3: Fetch all dashboards
      dashboards_result = fetch_dashboards
      return result unless dashboards_result[:success]

      # Step 4: Process each dashboard to ensure embedded config and get guest token
      processed_dashboards = []
      dashboards_result[:dashboards].each do |dashboard|
        embedded_config = ensure_embedded_config(dashboard["id"])
        next unless embedded_config[:success]

        guest_token_result = get_guest_token(dashboard["id"])
        next unless guest_token_result[:success]

        processed_dashboards << {
          id: dashboard["id"].to_s,
          dashboard_title: dashboard["dashboard_title"],
          embedded_id: embedded_config[:uuid],
          guest_token: guest_token_result[:guest_token]
        }
      end

      result.dashboards = processed_dashboards
      result
    rescue URI::InvalidURIError => e
      result.service_failure!(code: "invalid_superset_url", message: "Invalid Superset URL: #{e.message}")
    rescue => e
      result.service_failure!(code: "superset_auth_error", message: "Superset authentication failed: #{e.message}")
    end

    private

    attr_reader :organization, :user, :cookies, :csrf_token

    def login_to_superset
      uri = URI.join(superset_base_url, "/login/")
      http = create_http_client(uri)

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Referer"] = "#{superset_base_url}/login/"
      request["Cookie"] = cookies.join("; ")

      form_data = URI.encode_www_form({
        csrf_token: csrf_token,
        username: superset_username,
        password: superset_password
      })
      request.body = form_data

      response = http.request(request)
      store_cookies(response)

      unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
        result.service_failure!(code: "login_failed", message: "Failed to login to Superset: #{response.code} #{response.message}")
        return {success: false}
      end

      {success: true}
    end

    def get_csrf_token
      uri = URI.join(superset_base_url, "/api/v1/security/csrf_token/")
      http = create_http_client(uri)

      request = Net::HTTP::Get.new(uri.path)
      request["Accept"] = "application/json"

      response = http.request(request)
      store_cookies(response)

      unless response.is_a?(Net::HTTPSuccess)
        result.service_failure!(code: "csrf_failed", message: "Failed to get CSRF token: #{response.body}")
        return {success: false}
      end

      parsed_response = JSON.parse(response.body)
      csrf_token = parsed_response["result"]

      unless csrf_token
        result.service_failure!(code: "no_csrf_token", message: "No CSRF token received from Superset")
        return {success: false}
      end

      {success: true, csrf_token: csrf_token}
    rescue JSON::ParserError => e
      result.service_failure!(code: "invalid_response", message: "Invalid JSON response from Superset CSRF: #{e.message}")
      {success: false}
    end

    def fetch_dashboards
      uri = URI.join(superset_base_url, "/api/v1/dashboard/")
      http = create_http_client(uri)

      request = Net::HTTP::Get.new(uri.path)
      request["Accept"] = "application/json"
      request["X-CSRFToken"] = csrf_token
      request["Cookie"] = cookies.join("; ")

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        result.service_failure!(code: "fetch_dashboards_failed", message: "Failed to fetch dashboards: #{response.body}")
        return {success: false}
      end

      parsed_response = JSON.parse(response.body)
      dashboards = parsed_response["result"] || []

      {success: true, dashboards: dashboards}
    rescue JSON::ParserError => e
      result.service_failure!(code: "invalid_response", message: "Invalid JSON response from Superset dashboards: #{e.message}")
      {success: false}
    end

    def get_embedded_config(dashboard_id)
      uri = URI.join(superset_base_url, "/api/v1/dashboard/#{dashboard_id}/embedded")
      http = create_http_client(uri)

      request = Net::HTTP::Get.new(uri.path)
      request["Accept"] = "application/json"
      request["X-CSRFToken"] = csrf_token
      request["Cookie"] = cookies.join("; ")

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        parsed_response = JSON.parse(response.body)
        uuid = parsed_response["result"]&.[]("uuid")
        return {success: true, uuid: uuid, exists: true} if uuid
      end

      {success: true, exists: false}
    rescue JSON::ParserError
      {success: true, exists: false}
    end

    def create_embedded_config(dashboard_id)
      uri = URI.join(superset_base_url, "/api/v1/dashboard/#{dashboard_id}/embedded")
      http = create_http_client(uri)

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-CSRFToken"] = csrf_token
      request["Cookie"] = cookies.join("; ")

      body = {allowed_domains: []}
      request.body = body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        result.service_failure!(code: "create_embedded_failed", message: "Failed to create embedded config for dashboard #{dashboard_id}: #{response.body}")
        return {success: false}
      end

      parsed_response = JSON.parse(response.body)
      uuid = parsed_response["result"]&.[]("uuid")

      unless uuid
        result.service_failure!(code: "no_embedded_uuid", message: "No embedded UUID received for dashboard #{dashboard_id}")
        return {success: false}
      end

      {success: true, uuid: uuid}
    rescue JSON::ParserError => e
      result.service_failure!(code: "invalid_response", message: "Invalid JSON response from create embedded config: #{e.message}")
      {success: false}
    end

    def ensure_embedded_config(dashboard_id)
      embedded_config = get_embedded_config(dashboard_id)
      return {success: false} unless embedded_config[:success]

      return {success: true, uuid: embedded_config[:uuid]} if embedded_config[:exists]

      create_embedded_config(dashboard_id)
    end

    def get_guest_token(dashboard_id)
      uri = URI.join(superset_base_url, "/api/v1/security/guest_token/")
      http = create_http_client(uri)

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["X-CSRFToken"] = csrf_token
      request["Cookie"] = cookies.join("; ")

      body = {
        resources: [{id: dashboard_id.to_s, type: "dashboard"}],
        rls: [],
        user: guest_user_info
      }
      request.body = body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        result.service_failure!(code: "guest_token_failed", message: "Failed to get guest token for dashboard #{dashboard_id}: #{response.body}")
        return {success: false}
      end

      parsed_response = JSON.parse(response.body)
      guest_token = parsed_response["token"] || parsed_response["result"] || parsed_response["access_token"]

      unless guest_token
        result.service_failure!(code: "no_guest_token", message: "No guest token received for dashboard #{dashboard_id}")
        return {success: false}
      end

      {success: true, guest_token: guest_token}
    rescue JSON::ParserError => e
      result.service_failure!(code: "invalid_response", message: "Invalid JSON response from Superset guest token: #{e.message}")
      {success: false}
    end

    def create_http_client(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 30
      http.open_timeout = 30
      http
    end

    def store_cookies(response)
      return unless response["Set-Cookie"]

      new_cookies = response.get_fields("Set-Cookie")
      return unless new_cookies

      new_cookies.each do |cookie|
        cookie_value = cookie.split(";").first
        cookie_name = cookie_value.split("=").first

        @cookies.reject! { |c| c.start_with?("#{cookie_name}=") }

        @cookies << cookie_value
      end
    end

    def guest_user_info
      if user.present?
        user
      else
        {
          first_name: organization.name || "Guest",
          last_name: "User",
          username: "guest_#{organization.id}"
        }
      end
    end

    def superset_base_url
      ENV["SUPERSET_URL"] || raise("SUPERSET_URL environment variable not set")
    end

    def superset_username
      ENV["SUPERSET_USERNAME"] || raise("SUPERSET_USERNAME environment variable not set")
    end

    def superset_password
      ENV["SUPERSET_PASSWORD"] || raise("SUPERSET_PASSWORD environment variable not set")
    end
  end
end