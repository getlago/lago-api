# frozen_string_literal: true

RSpec.shared_context "with Stripe configured for customer" do
  let(:stripe_cus_id) { "cus_123456789" }
  let(:stripe_pm_id) { "pm_123456" }

  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider: stripe_provider, provider_customer_id: stripe_cus_id) }

  let(:stripe_customer_response) do
    File.read("spec/fixtures/stripe/customer_retrieve_response.json")
  end
  let(:stripe_payment_method_response) do
    JSON.parse(
      File.read("spec/fixtures/stripe/retrieve_payment_method.json"),
      symbolize_names: true
    ).merge!({
      id: stripe_pm_id,
      customer: stripe_cus_id
    })
  end

  before do
    customer.update! payment_provider: :stripe, payment_provider_code: stripe_provider.code
    stripe_customer

    stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
      .and_return(status: 200, body: stripe_customer_response)
    stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}/payment_methods/pm_123456")
      .and_return(status: 200, body: stripe_payment_method_response.to_json)

    WebMock.after_request do |request_signature, response|
      if request_signature.uri.path.match?(%r{/v1/payment_intents})
        request_body_hash = if request_signature.url_encoded?
          Rack::Utils.parse_nested_query(request_signature.body)
        elsif request_signature.body.json_encoded?
          JSON.parse(request_signature.body)
        end

        Jobs::MockStripeWebhookEventJob.perform_later(
          organization,
          request_body_hash,
          JSON.parse(response.body)
        )
      end
    end
  end
end
