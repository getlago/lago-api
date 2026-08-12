# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::RateCardRateSerializer do
  subject(:serializer) { described_class.new(rate, root_name: "rate") }

  let(:rate) { create(:rate_card_rate) }

  it "serializes the rate" do
    payload = serializer.serialize

    expect(payload[:lago_id]).to eq(rate.id)
    expect(payload[:code]).to eq(rate.code)
    expect(payload[:effective_from]).to eq(rate.effective_from.iso8601)
    expect(payload[:status]).to eq("active")
    expect(payload[:rate_model]).to eq(rate.rate_model)
  end
end
