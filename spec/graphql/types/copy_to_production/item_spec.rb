# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::Item do
  subject { described_class }

  it { is_expected.to have_field(:code).of_type("String") }
  it { is_expected.to have_field(:id).of_type("ID!") }
  it { is_expected.to have_field(:item_type).of_type("CopyToProductionItemTypeEnum!") }
  it { is_expected.to have_field(:name).of_type("String") }

  describe "#code and #name" do
    let(:context) { GraphQL::Query.new(LagoApiSchema, "{ __typename }").context }
    let(:rate_card) { create(:rate_card, code: "seat_eur", name: "Seat EUR") }

    it "answers those of the record" do
      type = described_class.authorized_new(CopyToProduction::BaseService::Entry.new(item_type: "rate_card", record: rate_card), context)

      expect([type.code, type.name]).to eq(["seat_eur", "Seat EUR"])
    end

    it "answers those of the rate card of a plan rate card" do
      plan_rate_card = create(:plan_rate_card, rate_card:)
      type = described_class.authorized_new(CopyToProduction::BaseService::Entry.new(item_type: "plan_rate_card", record: plan_rate_card), context)

      expect([type.code, type.name]).to eq(["seat_eur", "Seat EUR"])
    end
  end
end
