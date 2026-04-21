# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotesQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, latest_version_only:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:pagination) { nil }
  let(:filters) { {} }
  let(:latest_version_only) { false }

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

    context "with a page past the last page" do
      let(:pagination) { {page: 99, limit: 2} }

      it "returns an empty collection while keeping metadata stable" do
        expect(result).to be_success
        expect(result.quotes).to be_empty
        expect(result.quotes.total_count).to eq(4)
        expect(result.quotes.total_pages).to eq(2)
      end
    end
  end

  describe "filters" do
    context "with customer filter" do
      let(:other_customer) { create(:customer, organization:) }
      let!(:matching_quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:other_quote) { create(:quote, organization:, customer: other_customer, sequential_id: 2, version: 1, number: "QT-2024-0002") }
      let(:filters) { {customer: [customer.id]} }

      it "returns only quotes for the passed customer" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([matching_quote.id])
      end
    end

    context "with status filter" do
      let!(:draft_quote) { create(:quote, organization:, customer:, status: :draft, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:approved_quote) { create(:quote, organization:, customer:, status: :approved, sequential_id: 2, version: 1, number: "QT-2024-0002") }
      let!(:voided_quote) { create(:quote, organization:, customer:, status: :voided, sequential_id: 3, version: 1, number: "QT-2024-0003") }
      let(:filters) { {status: ["draft", "voided"]} }

      it "returns only quotes with the passed statuses" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to match_array([draft_quote.id, voided_quote.id])
      end
    end

    context "with number filter" do
      let!(:matching_quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:other_quote) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002") }
      let(:filters) { {number: ["QT-2024-0001"]} }

      it "returns only quotes matching the numbers" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([matching_quote.id])
      end
    end

    context "with version filter" do
      let!(:v1) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:v2) { create(:quote, organization:, customer:, sequential_id: 1, version: 2, number: "QT-2024-0001") }
      let!(:v3) { create(:quote, organization:, customer:, sequential_id: 1, version: 3, number: "QT-2024-0001") }
      let(:filters) { {version: [1, 3]} }

      it "returns only quotes at the passed versions" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to match_array([v1.id, v3.id])
      end
    end

    context "with date window" do
      let!(:old_quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001", created_at: 10.days.ago) }
      let!(:recent_quote) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002", created_at: 1.day.ago) }
      let(:filters) { {from_date: 5.days.ago.to_date, to_date: Date.today} }

      it "returns only quotes created within the window" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([recent_quote.id])
      end
    end

    context "with from_date as a Date object" do
      let!(:quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let(:filters) { {from_date: Date.today - 1} }

      it "does not fail validation" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([quote.id])
      end
    end

    context "with to_date only" do
      let!(:yesterday_quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001", created_at: 1.day.ago) }
      let!(:today_quote) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002", created_at: Time.current) }
      let(:filters) { {to_date: Date.today} }

      it "returns quotes created up to the end of to_date" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to match_array([yesterday_quote.id, today_quote.id])
      end
    end

    context "with to_date equal to the created day" do
      let!(:quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001", created_at: Time.current) }
      let(:filters) { {to_date: Date.current} }

      it "includes quotes created earlier the same day" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([quote.id])
      end
    end

    context "with owners filter" do
      let(:user_one) { create(:user) }
      let(:user_two) { create(:user) }
      let!(:matching_quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:other_quote) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002") }
      let(:filters) { {owners: [user_one.id]} }

      before do
        create(:quote_owner, organization:, quote: matching_quote, user: user_one)
        create(:quote_owner, organization:, quote: other_quote, user: user_two)
      end

      it "returns only quotes with the matching owners" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([matching_quote.id])
      end
    end

    context "with owners filter matching multiple users" do
      let(:user_one) { create(:user) }
      let(:user_two) { create(:user) }
      let!(:quote) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let(:filters) { {owners: [user_one.id, user_two.id]} }

      before do
        create(:quote_owner, organization:, quote:, user: user_one)
        create(:quote_owner, organization:, quote:, user: user_two)
      end

      it "returns the quote exactly once" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([quote.id])
      end
    end

    context "with latest_version_only" do
      let!(:q1_v1) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:q1_v2) { create(:quote, organization:, customer:, sequential_id: 1, version: 2, number: "QT-2024-0001") }
      let!(:q1_v3) { create(:quote, organization:, customer:, sequential_id: 1, version: 3, number: "QT-2024-0001") }
      let!(:q2_v1) { create(:quote, organization:, customer:, sequential_id: 2, version: 1, number: "QT-2024-0002") }
      let(:latest_version_only) { true }

      it "returns the highest version per sequential_id" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to match_array([q1_v3.id, q2_v1.id])
      end

      it "orders the deduped set by number DESC then version DESC" do
        expect(result.quotes.pluck(:number, :version)).to eq([
          ["QT-2024-0002", 1],
          ["QT-2024-0001", 3]
        ])
      end
    end

    context "with latest_version_only combined with a status filter" do
      let!(:draft_v1) { create(:quote, organization:, customer:, sequential_id: 10, version: 1, number: "QT-2025-0010", status: :draft) }
      let!(:approved_v2) { create(:quote, organization:, customer:, sequential_id: 10, version: 2, number: "QT-2025-0010", status: :approved) }

      let(:latest_version_only) { true }
      let(:filters) { {status: ["draft"]} }

      it "filters first, then picks the latest among the filtered versions" do
        # Intended behaviour: when a quote has v1=draft and v2=approved, and the
        # caller filters on status=draft with latest_version_only, we surface v1.
        # The filter applies BEFORE the DISTINCT ON roll-up.
        expect(result.quotes.pluck(:number, :version)).to eq([
          ["QT-2025-0010", 1]
        ])
      end
    end

    context "with latest_version_only combined with owners filter" do
      let(:user_one) { create(:user) }
      let!(:q1_v1) { create(:quote, organization:, customer:, sequential_id: 1, version: 1, number: "QT-2024-0001") }
      let!(:q1_v2) { create(:quote, organization:, customer:, sequential_id: 1, version: 2, number: "QT-2024-0001") }
      let(:filters) { {owners: [user_one.id]} }
      let(:latest_version_only) { true }

      before do
        create(:quote_owner, organization:, quote: q1_v1, user: user_one)
        create(:quote_owner, organization:, quote: q1_v2, user: user_one)
      end

      it "combines filters without raising an ambiguous column error" do
        expect(result).to be_success
        expect(result.quotes.pluck(:id)).to eq([q1_v2.id])
      end
    end
  end
end
