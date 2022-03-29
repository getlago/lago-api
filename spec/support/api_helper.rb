# frozen_string_literal: true

module ApiHelper
  def get_with_token(organization, path, params = {}, headers = {})
    set_headers(organization, headers)
    get(path, params: params, headers: headers)
  end

  def post_with_token(organization, path, params = {}, headers = {})
    set_headers(organization, headers)
    post(path, params: params.to_json, headers: headers)
  end

  def put_with_token(organization, path, params = {}, headers = {})
    set_headers(organization, headers)
    put(path, params: params.to_json, headers: headers)
  end

  def delete_with_token(organization, path, params = {}, headers = {})
    set_headers(organization, headers)
    delete(path, params: params.to_json, headers: headers)
  end

  private

  def set_headers(organization, headers)
    headers['Content-Type'] = 'application/json'
    headers['Accept'] = 'application/json'
    headers['Authorization'] = "Bearer #{organization.api_key}"
  end
end
