# frozen_string_literal: true

module CommonScenarioHelper
  def api_call(perform_jobs: true, raise_on_error: true)
    yield

    if raise_on_error && response.status >= 400
      request = response.request
      message_parts = ["API call failed:",
        "- Method: #{request.method}",
        "- Path: #{request.path}",
        "- Request body: #{request.body.read}",
        "- HTTP status: #{response.status}",
        "- Response body: #{response.body}"]
      message = message_parts.join("\n")
      raise message
    end

    perform_all_enqueued_jobs if perform_jobs
    json.with_indifferent_access
  end

  def clock_job
    yield
    perform_all_enqueued_jobs
  end
end
