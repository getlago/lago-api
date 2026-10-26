# frozen_string_literal: true

# The whole 404 body of a native v2 endpoint. be_not_found_error checks the v1 one.
RSpec::Matchers.define :be_v2_not_found_error do |resource|
  expected_body = {"code" => "#{resource}_not_found", "details" => []}

  match do |response|
    response.status == 404 && JSON.parse(response.body) == expected_body
  rescue JSON::ParserError
    false
  end

  failure_message do |response|
    "expected a 404 with #{expected_body.inspect}, got #{response.status} with #{response.body}"
  end

  failure_message_when_negated do
    "expected response not to be a v2 not found error for #{resource}, but it was"
  end

  description do
    "be a v2 not found error response for #{resource}"
  end
end
