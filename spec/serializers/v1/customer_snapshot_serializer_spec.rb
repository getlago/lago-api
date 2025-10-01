# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::CustomerSnapshotSerializer do
  subject(:serializer) { described_class.new(customer_snapshot, root_name: "customer_snapshot") }

  let(:customer_snapshot) { create(:customer_snapshot) }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the object" do
    expect(result["customer_snapshot"]["display_name"]).to eq(customer_snapshot.display_name)
    expect(result["customer_snapshot"]["firstname"]).to eq(customer_snapshot.firstname)
    expect(result["customer_snapshot"]["lastname"]).to eq(customer_snapshot.lastname)
    expect(result["customer_snapshot"]["email"]).to eq(customer_snapshot.email)
    expect(result["customer_snapshot"]["phone"]).to eq(customer_snapshot.phone)
    expect(result["customer_snapshot"]["url"]).to eq(customer_snapshot.url)
    expect(result["customer_snapshot"]["tax_identification_number"]).to eq(customer_snapshot.tax_identification_number)
    expect(result["customer_snapshot"]["applicable_timezone"]).to eq(customer_snapshot.applicable_timezone)
    expect(result["customer_snapshot"]["address_line1"]).to eq(customer_snapshot.address_line1)
    expect(result["customer_snapshot"]["address_line2"]).to eq(customer_snapshot.address_line2)
    expect(result["customer_snapshot"]["city"]).to eq(customer_snapshot.city)
    expect(result["customer_snapshot"]["state"]).to eq(customer_snapshot.state)
    expect(result["customer_snapshot"]["zipcode"]).to eq(customer_snapshot.zipcode)
    expect(result["customer_snapshot"]["country"]).to eq(customer_snapshot.country)
    expect(result["customer_snapshot"]["legal_name"]).to eq(customer_snapshot.legal_name)
    expect(result["customer_snapshot"]["legal_number"]).to eq(customer_snapshot.legal_number)
  end

  it "serializes the shipping address" do
    expected_shipping_address = {
      "address_line1" => customer_snapshot.shipping_address_line1,
      "address_line2" => customer_snapshot.shipping_address_line2,
      "city" => customer_snapshot.shipping_city,
      "state" => customer_snapshot.shipping_state,
      "zipcode" => customer_snapshot.shipping_zipcode,
      "country" => customer_snapshot.shipping_country
    }

    expect(result["customer_snapshot"]["shipping_address"]).to eq(expected_shipping_address)
  end
end
