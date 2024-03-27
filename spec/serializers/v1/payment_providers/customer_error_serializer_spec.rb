# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::PaymentProviders::CustomerErrorSerializer do
  subject(:serializer) { described_class.new(customer, options) }

  let(:customer) { create(:customer) }
  let(:options) do
    {
      "provider_error" => {
        "error_message" => "message",
        "error_code" => "code"
      }
    }.with_indifferent_access
  end

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result["data"]["lago_customer_id"]).to eq(customer.id)
      expect(result["data"]["external_customer_id"]).to eq(customer.external_id)
      expect(result["data"]["payment_provider"]).to eq(customer.payment_provider)
      expect(result["data"]["payment_provider_code"]).to eq(customer.payment_provider_code)
      expect(result["data"]["provider_error"]).to eq(options[:provider_error])
    end
  end
end
