# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::Client do
  subject(:client) { described_class.new(payment_provider:) }

  let(:organization) { create(:organization) }
  let(:payment_provider) do
    build(:paystack_provider, organization:, secret_key: "sk_test_paystack")
  end
  let(:response_body) { {"status" => true, "data" => {"id" => 123}} }
  let(:headers) do
    {
      "Authorization" => "Bearer sk_test_paystack",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end

  [
    [:create_customer, :post, "/customer", [{email: "customer@example.com"}]],
    [:update_customer, :put, "/customer/CUS_123", ["CUS_123", {first_name: "Jane"}]],
    [:initialize_transaction, :post, "/transaction/initialize", [{amount: 10_000}]],
    [:verify_transaction, :get, "/transaction/verify/lago-reference", ["lago-reference"]],
    [:charge_authorization, :post, "/transaction/charge_authorization", [{authorization_code: "AUTH_123"}]],
    [:create_refund, :post, "/refund", [{transaction: "4099260516"}]],
    [:fetch_refund, :get, "/refund/3018284", ["3018284"]]
  ].each do |client_method, http_method, path, arguments|
    describe "##{client_method}" do
      it "sends an authenticated request and returns the parsed response" do
        request = stub_request(http_method, "#{PaymentProviders::PaystackProvider::API_URL}#{path}")
          .with(headers:)
        request = request.with(body: arguments.last.to_json) unless http_method == :get
        request.to_return(status: 200, body: response_body.to_json)

        expect(client.public_send(client_method, *arguments)).to eq(response_body)
        expect(request).to have_been_requested.once
      end
    end
  end

  describe "#retry_refund" do
    it "sends the customer refund account details" do
      refund_account_details = {account_number: "0123456789", bank_code: "058"}
      request = stub_request(
        :post,
        "#{PaymentProviders::PaystackProvider::API_URL}/refund/retry_with_customer_details/3018284"
      ).with(
        headers:,
        body: {refund_account_details:}.to_json
      ).to_return(status: 200, body: response_body.to_json)

      result = client.retry_refund("3018284", refund_account_details:)

      expect(result).to eq(response_body)
      expect(request).to have_been_requested.once
    end
  end

  context "when Paystack rejects the request" do
    it "raises a Paystack error with the provider response" do
      response = {"status" => false, "message" => "Invalid authorization code"}
      stub_request(
        :post,
        "#{PaymentProviders::PaystackProvider::API_URL}/transaction/charge_authorization"
      ).to_return(status: 200, body: response.to_json)

      expect do
        client.charge_authorization(authorization_code: "AUTH_invalid")
      end.to raise_error(PaymentProviders::Paystack::Client::Error) do |error|
        expect(error.message).to eq("Invalid authorization code")
        expect(error.response).to eq(response)
      end
    end
  end

  context "when Paystack returns invalid JSON" do
    it "raises a Paystack error" do
      stub_request(
        :post,
        "#{PaymentProviders::PaystackProvider::API_URL}/transaction/initialize"
      ).to_return(status: 200, body: "not-json")

      expect do
        client.initialize_transaction(amount: 10_000)
      end.to raise_error(PaymentProviders::Paystack::Client::Error, "Invalid Paystack response")
    end
  end

  context "when Paystack returns an HTTP error" do
    it "propagates the HTTP error" do
      stub_request(
        :get,
        "#{PaymentProviders::PaystackProvider::API_URL}/transaction/verify/lago-reference"
      ).to_return(status: 401, body: {status: false, message: "Invalid key"}.to_json)

      expect do
        client.verify_transaction("lago-reference")
      end.to raise_error(LagoHttpClient::HttpError)
    end
  end
end
