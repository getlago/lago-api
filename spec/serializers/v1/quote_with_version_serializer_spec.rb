# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::QuoteWithVersionSerializer do
  subject(:serializer) { described_class.new(quote_version, root_name: "quote") }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) do
    create(:quote_version, :voided, organization:, quote:, currency: "EUR", content: "<p>Terms</p>")
  end

  it "serializes the quote" do
    result = JSON.parse(serializer.to_json)

    expect(result["quote"]).to include(
      "lago_id" => quote.id,
      "number" => quote.number,
      "order_type" => quote.order_type,
      "lago_customer_id" => customer.id,
      "lago_subscription_id" => nil,
      "lago_organization_id" => organization.id,
      "created_at" => quote.created_at.iso8601,
      "updated_at" => quote.updated_at.iso8601
    )
  end

  it "serializes the version the event happened to" do
    result = JSON.parse(serializer.to_json)

    expect(result["quote"]["version"]).to include(
      "lago_id" => quote_version.id,
      "lago_quote_id" => quote.id,
      "version" => quote_version.version,
      "status" => "voided",
      "void_reason" => "manual",
      "currency" => "EUR"
    )
  end

  it "omits the heavy and quote-level attributes" do
    result = JSON.parse(serializer.to_json)

    expect(result["quote"]).not_to have_key("current_version")
    expect(result["quote"]).not_to have_key("owners")
    expect(result["quote"]["version"]).not_to have_key("content")
    expect(result["quote"]["version"]).not_to have_key("billing_items")
  end

  context "when a newer version supersedes the serialized one" do
    before do
      create(:quote_version, organization:, quote:, sequential_id: quote_version.sequential_id + 1)
    end

    it "still serializes the version it was given" do
      result = JSON.parse(serializer.to_json)

      expect(quote.reload.current_version).not_to eq(quote_version)
      expect(result["quote"]["version"]["lago_id"]).to eq(quote_version.id)
      expect(result["quote"]["version"]["status"]).to eq("voided")
    end
  end
end
