# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Customers::CheckoutUrlSerializer do
  subject(:result) do
    model = described_class::CheckoutUrl.new(customer:, url: "https://checkout.test/abc")
    JSON.parse(described_class.new(model, root_name: "checkout_url").to_json)["checkout_url"]
  end

  let(:customer) { create(:customer, payment_provider: "stripe", payment_provider_code: "stripe_eu") }

  it "serializes the customer's checkout link" do
    expect(result).to eq(
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "payment_provider" => "stripe",
      "payment_provider_code" => "stripe_eu",
      "checkout_url" => "https://checkout.test/abc"
    )
  end
end
