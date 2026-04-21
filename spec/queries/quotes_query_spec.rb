# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotesQuery do
  subject(:result) do
    described_class.call(organization:, pagination:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:pagination) { nil }

  describe "ordering" do
    let!(:q1_v1) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
    let!(:q1_v2) { create(:quote, organization:, customer:, sequential_id: 1, version: 2, number: "QT-2024-0001") }
    let!(:q1_v3) { create(:quote, organization:, customer:, sequential_id: 1, version: 3, number: "QT-2024-0001") }
    let!(:q2_v1) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002") }

    it "orders by number DESC then version DESC" do
      expect(result).to be_success
      expect(result.quotes.pluck(:number, :version)).to eq([
        ["QT-2024-0002", 1],
        ["QT-2024-0001", 3],
        ["QT-2024-0001", 2],
        ["QT-2024-0001", 1]
      ])
    end
  end

  describe "organization scoping" do
    let(:other_organization) { create(:organization) }
    let(:other_customer) { create(:customer, organization: other_organization) }
    let!(:quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
    let!(:other_quote) { create(:quote, organization: other_organization, customer: other_customer, sequential_id: 1, version: 1, number: "QT-2024-0099") }

    it "only returns quotes belonging to the given organization" do
      expect(result).to be_success
      expect(result.quotes.pluck(:id)).to eq([quote.id])
    end
  end

  describe "empty result" do
    it "returns a successful result with no quotes" do
      expect(result).to be_success
      expect(result.quotes).to be_empty
    end
  end

  describe "pagination" do
    let!(:quotes) do
      (1..4).map do |seq|
        create(
          :quote,
          organization:,
          customer:,
          sequential_id: seq,
          version: 1,
          number: format("QT-2024-%04d", seq)
        )
      end
    end

    context "with first page" do
      let(:pagination) { {page: 1, limit: 2} }

      it "returns the first page" do
        expect(result).to be_success
        expect(result.quotes.pluck(:number)).to eq(["QT-2024-0004", "QT-2024-0003"])
        expect(result.quotes.current_page).to eq(1)
        expect(result.quotes.total_count).to eq(4)
        expect(result.quotes.total_pages).to eq(2)
      end
    end

    context "with second page" do
      let(:pagination) { {page: 2, limit: 2} }

      it "returns the next page in the expected order" do
        expect(result).to be_success
        expect(result.quotes.pluck(:number)).to eq(["QT-2024-0002", "QT-2024-0001"])
      end
    end

    it "keeps ordering stable across pages" do
      page1 = described_class.call(organization:, pagination: {page: 1, limit: 2}).quotes.pluck(:number, :version)
      page2 = described_class.call(organization:, pagination: {page: 2, limit: 2}).quotes.pluck(:number, :version)

      expect(page1 + page2).to eq([
        ["QT-2024-0004", 1],
        ["QT-2024-0003", 1],
        ["QT-2024-0002", 1],
        ["QT-2024-0001", 1]
      ])
    end
  end
end
