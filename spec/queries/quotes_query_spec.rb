# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotesQuery do
  subject(:result) do
    described_class.call(
      organization:,
      filters:,
      latest_version_only:,
      pagination: {page: nil, limit: nil}
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:filters) { {} }
  let(:latest_version_only) { false }

  describe "ordering" do
    let!(:q1_v1) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001", status: :voided, voided_at: Time.current, void_reason: :manual) }
    let!(:q1_v2) { create(:quote, organization:, customer:, sequential_id: 1, version: 2, number: "QT-2024-0001", status: :voided, voided_at: Time.current, void_reason: :manual) }
    let!(:q1_v3) { create(:quote, organization:, customer:, sequential_id: 1, version: 3, number: "QT-2024-0001", status: :draft) }
    let!(:q2_v1) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002", status: :draft) }

    it "orders by number DESC then version DESC" do
      expect(result.quotes.pluck(:number, :version)).to eq([
        ["QT-2024-0002", 1],
        ["QT-2024-0001", 3],
        ["QT-2024-0001", 2],
        ["QT-2024-0001", 1]
      ])
    end

    context "with latest_version_only" do
      let(:latest_version_only) { true }

      it "returns only the highest version per sequential_id" do
        numbers_versions = result.quotes.pluck(:number, :version)
        expect(numbers_versions).to match_array([
          ["QT-2024-0001", 3],
          ["QT-2024-0002", 1]
        ])
      end
    end

    context "with latest_version_only combined with owners filter" do
      let(:latest_version_only) { true }
      let(:user) { create(:membership, organization:).user }
      let(:filters) { {owners: [user.id]} }

      before do
        create(:quote_owner, organization:, quote: q1_v3, user:)
        create(:quote_owner, organization:, quote: q2_v1, user:)
      end

      it "returns the latest version per sequential_id without raising" do
        numbers_versions = result.quotes.pluck(:number, :version)
        expect(numbers_versions).to match_array([
          ["QT-2024-0001", 3],
          ["QT-2024-0002", 1]
        ])
      end
    end
  end

  describe "date filtering" do
    let!(:older) do
      create(
        :quote,
        organization:,
        customer:,
        sequential_id: 1,
        version: 1,
        number: "QT-2024-0001",
        created_at: Time.zone.parse("2024-01-01 10:00:00")
      )
    end
    let!(:inside) do
      create(
        :quote,
        organization:,
        customer:,
        sequential_id: 2,
        version: 1,
        number: "QT-2024-0002",
        created_at: Time.zone.parse("2024-02-15 10:00:00")
      )
    end
    let!(:newer) do
      create(
        :quote,
        organization:,
        customer:,
        sequential_id: 3,
        version: 1,
        number: "QT-2024-0003",
        created_at: Time.zone.parse("2024-03-10 10:00:00")
      )
    end
    let(:filters) do
      {
        from_date: Date.new(2024, 2, 1),
        to_date: Date.new(2024, 2, 28)
      }
    end

    it "only returns quotes created within the date window" do
      expect(result.quotes.pluck(:number)).to eq(["QT-2024-0002"])
    end
  end

  describe "owners filter deduplication" do
    let(:user1) { create(:membership, organization:).user }
    let(:user2) { create(:membership, organization:).user }
    let!(:quote) do
      create(
        :quote,
        organization:,
        customer:,
        sequential_id: 1,
        version: 1,
        number: "QT-2024-0001"
      )
    end
    let(:filters) { {owners: [user1.id, user2.id]} }

    before do
      create(:quote_owner, organization:, quote:, user: user1)
      create(:quote_owner, organization:, quote:, user: user2)
    end

    it "returns each matching quote only once" do
      expect(result.quotes.to_a.map(&:id)).to eq([quote.id])
    end
  end
end
