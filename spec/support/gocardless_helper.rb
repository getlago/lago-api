# frozen_string_literal: true

# Stubs GoCardless API calls with WebMock, so the gem raises the same error class it raises
# for a real answer (a `validation_failed` body gives `GoCardlessPro::ValidationError`).
#
#         stub_gocardless_error(:post, "/payments", status: 422, type: "validation_failed")
module GocardlessHelper
  def stub_gocardless_error(method, path, status:, type:, message: "error")
    stub_request(method, "https://api-sandbox.gocardless.com#{path}").to_return(
      status:,
      headers: {"Content-Type" => "application/json"},
      body: {error: {type:, code: status, message:, errors: [], request_id: "req_123"}}.to_json
    )
  end
end
