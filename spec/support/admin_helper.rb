# frozen_string_literal: true

module AdminHelper
  ADMIN_API_KEY = "admin-api-key"

  def admin_put(path, params = {}, headers = {})
    apply_headers(headers)
    put(path, params: params.to_json, headers:)
  end

  def admin_post(path, params = {}, headers = {})
    apply_headers(headers)
    post(path, params: params.to_json, headers:)
  end

  def admin_headers(api_key = ADMIN_API_KEY)
    {"X-Admin-API-Key" => api_key}
  end

  def json
    return response.body unless response.media_type.include?("json")

    JSON.parse(response.body, symbolize_names: true)
  end

  private

  def apply_headers(headers)
    headers["Content-Type"] = "application/json"
    headers["Accept"] = "application/json"
  end
end

RSpec.configure do |config|
  config.before(:each, type: :admin) do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_API_KEY").and_return(AdminHelper::ADMIN_API_KEY)
  end
end
