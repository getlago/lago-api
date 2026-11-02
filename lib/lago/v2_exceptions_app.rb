# frozen_string_literal: true

module Lago
  # The config.exceptions_app: errors Rails answers itself, such as a 500, a malformed JSON body or
  # query string, or an unknown format. A request that a native v2 controller handled, or that reached
  # no controller under /api/v2, gets the v2 body; every other request gets the Rails default.
  #
  # A Rack app rather than a controller: a controller would read the params of the failed request
  # again, and fail again on a malformed body.
  class V2ExceptionsApp
    # The codes of the statuses Rails answers itself, owned here so that they do not follow Rack's
    # reason phrases, which change between versions. A 404 is resource_not_found on every v2 path.
    CODES = {
      400 => "bad_request",
      404 => "resource_not_found",
      405 => "method_not_allowed",
      406 => "not_acceptable",
      409 => "conflict",
      422 => "unprocessable_content",
      429 => "too_many_requests",
      500 => "internal_server_error",
      501 => "not_implemented"
    }.freeze

    def initialize(fallback = ActionDispatch::PublicExceptions.new(Rails.public_path))
      @fallback = fallback
    end

    def call(env)
      if v2?(env)
        # ShowExceptions passes the status as the path.
        status = env["PATH_INFO"].delete_prefix("/").to_i
        body = {code: code(status), details: []}.to_json
        [status, {"content-type" => "application/json; charset=utf-8", "x-lago-endpoint-status" => "beta"}, [body]]
      else
        fallback.call(env)
      end
    end

    private

    attr_reader :fallback

    # The shared /api/v2 routes keep the answers of their v1 controllers.
    def v2?(env)
      controller = env["action_controller.instance"]
      if controller
        controller.is_a?(Api::V2::BaseController) || controller.is_a?(Api::UnknownV2RoutesController)
      else
        path = env["action_dispatch.original_path"].to_s
        path == "/api/v2" || path.start_with?("/api/v2/")
      end
    end

    def code(status)
      CODES.fetch(status) { (status >= 500) ? "internal_server_error" : "bad_request" }
    end
  end
end
