# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::QuoteVersionSerializer do
  subject(:serializer) { described_class.new(quote_version, root_name: "quote_version") }

  let(:quote_version) { create(:quote_version) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    expect(result["quote_version"]).to include(
      "lago_id" => quote_version.id,
      "quote_id" => quote_version.quote_id,
      "version" => quote_version.version,
      "number" => quote_version.quote.number,
      "status" => quote_version.status,
      "void_reason" => quote_version.void_reason,
      "voided_at" => quote_version.voided_at&.iso8601,
      "approved_at" => quote_version.approved_at&.iso8601,
      "created_at" => quote_version.created_at.iso8601
    )
  end
end
