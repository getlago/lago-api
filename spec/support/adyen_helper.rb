# frozen_string_literal: true

# Stubs Adyen Checkout API calls with WebMock. The gem raises only on 401 and 403; any other
# status comes back as a result.
#
#         stub_adyen_checkout("payments", status: 422, body: {errorType: "validation", message: "Invalid card number"})
module AdyenHelper
  def stub_adyen_checkout(endpoint, status: 200, body: {})
    stub_request(:post, %r{\Ahttps://checkout-test\.adyen\.com/v\d+/#{endpoint}\z})
      .to_return(status:, headers: {"Content-Type" => "application/json"}, body: body.to_json)
  end
end
