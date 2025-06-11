# frozen_string_literal: true

module V1
  class ApiLogSerializer < ModelSerializer
    def serialize
      {
        request_id: model.request_id,
        api_version: model.api_version,
        client: model.client,
        request_body: model.request_body,
        request_response: model.request_response,
        request_path: model.request_path,
        request_origin: model.request_origin,
        request_http_method: model.request_http_method,
        request_http_status: model.request_http_status,
        logged_at: model.logged_at.iso8601,
        created_at: model.created_at.iso8601
      }
    end
  end
end
