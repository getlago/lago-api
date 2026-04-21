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
  end
end
