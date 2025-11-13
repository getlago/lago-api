# frozen_string_literal: true

class SupersetAuthService < BaseService
  Result = BaseResult[:guest_token, :access_token]

  def initialize(organization:, dashboard_id:, user: nil)
    @organization = organization
    @dashboard_id = dashboard_id
    @user = user
    @cookies = []

    super()
  end

  def call
    # Step 1: Login to get access token
    login_result = login_to_superset
    return result unless login_result[:success]

    # Step 2: Get CSRF token
    csrf_result = get_csrf_token(login_result[:access_token])
    return result unless csrf_result[:success]

    # Step 3: Get guest token
    guest_token_result = get_guest_token(
      login_result[:access_token],
      csrf_result[:csrf_token]
    )
    return result unless guest_token_result[:success]

    result.guest_token = guest_token_result[:guest_token]
    result.access_token = login_result[:access_token]
    result
  rescue URI::InvalidURIError => e
    result.service_failure!(code: "invalid_superset_url", message: "Invalid Superset URL: #{e.message}")
  rescue => e
    result.service_failure!(code: "superset_auth_error", message: "Superset authentication failed: #{e.message}")
  end

  private

  attr_reader :organization, :dashboard_id, :user, :cookies

  def login_to_superset
    uri = URI.join(superset_base_url, "/api/v1/security/login")
    http = create_http_client(uri)

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"

    body = {
      username: superset_username,
      password: superset_password,
      provider: "db",
      refresh: true
    }
    request.body = body.to_json

    response = http.request(request)
    store_cookies(response)

    unless response.is_a?(Net::HTTPSuccess)
      result.service_failure!(code: "login_failed", message: "Failed to login to Superset: #{response.body}")
      return {success: false}
    end

    parsed_response = JSON.parse(response.body)
    access_token = parsed_response["access_token"]

    unless access_token
      result.service_failure!(code: "no_access_token", message: "No access token received from Superset")
      return {success: false}
    end

    {success: true, access_token: access_token}
  rescue JSON::ParserError => e
    result.service_failure!(code: "invalid_response", message: "Invalid JSON response from Superset login: #{e.message}")
    {success: false}
  end

  def get_csrf_token(access_token)
    uri = URI.join(superset_base_url, "/api/v1/security/csrf_token/")
    http = create_http_client(uri)

    request = Net::HTTP::Get.new(uri.path)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request["Referer"] = "#{superset_base_url}/"
    request["Cookie"] = cookies.join("; ")

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

  def get_guest_token(access_token, csrf_token)
    uri = URI.join(superset_base_url, "/api/v1/security/guest_token/")
    http = create_http_client(uri)

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request["X-CSRFToken"] = csrf_token
    request["Referer"] = "#{superset_base_url}/"
    request["Cookie"] = cookies.join("; ")

    body = {
      resources: [{id: dashboard_id, type: "dashboard"}],
      rls: [],
      user: guest_user_info
    }
    request.body = body.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      result.service_failure!(code: "guest_token_failed", message: "Failed to get guest token: #{response.body}")
      return {success: false}
    end

    parsed_response = JSON.parse(response.body)
    # Superset can return the token in different keys depending on version
    guest_token = parsed_response["token"] || parsed_response["result"] || parsed_response["access_token"]

    unless guest_token
      result.service_failure!(code: "no_guest_token", message: "No guest token received from Superset")
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
