# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeaturesQuery do
  let_it_be(:organization) { create(:organization) }
  let!(:feature1) { create(:feature, organization:, code: "seats", name: "Number of seats") }
  let!(:feature2) { create(:feature, organization:, code: "storage", name: "Storage") }
  let!(:feature3) { create(:feature, organization:, code: "api_calls", name: "API Calls") }

  let_it_be(:other_organization_feature) { create(:feature, organization: create(:organization), code: "other") }

  describe "#call" do
    subject { described_class.call(organization:, pagination:, search_term:, filters:) }

    let(:pagination) { {page: nil, limit: nil} }
    let(:search_term) { nil }
    let(:filters) { {} }

    it "returns features for the organization" do
      result = subject

      expect(result).to be_success
      expect(result.features).to contain_exactly(feature1, feature2, feature3)
    end

    it "applies pagination" do
      result = described_class.call(
        organization:,
        pagination: {page: 1, limit: 2}
      )

      expect(result).to be_success
      expect(result.features.count).to eq(2)
    end

    it "applies search term to name" do
      result = described_class.call(
        organization:,
        search_term: "seats"
      )

      expect(result).to be_success
      expect(result.features).to include(feature1)
      expect(result.features).not_to include(feature2, feature3)
    end

    it "applies search term to code" do
      result = described_class.call(
        organization:,
        search_term: "storage"
      )

      expect(result).to be_success
      expect(result.features).to include(feature2)
      expect(result.features).not_to include(feature1, feature3)
    end

    it "applies search term with partial matches" do
      result = described_class.call(
        organization:,
        search_term: "api"
      )

      expect(result).to be_success
      expect(result.features).to include(feature3)
      expect(result.features).not_to include(feature1, feature2)
    end

    it "applies consistent ordering" do
      result = subject

      expect(result).to be_success
      expect(result.features.to_a).to eq(result.features.order(created_at: :desc, id: :asc).to_a)
    end

    context "with pagination parameters" do
      let(:pagination) { {page: 1, limit: 1} }

      it "returns paginated results" do
        result = subject

        expect(result).to be_success
        expect(result.features.count).to eq(1)
        expect(result.features.first.code).to eq(feature3.code)
      end

      it "returns different results for different pages" do
        result1 = described_class.call(organization:, pagination: {page: 1, limit: 1})
        result2 = described_class.call(organization:, pagination: {page: 2, limit: 1})

        expect(result1.features).not_to eq(result2.features)
      end
    end

    context "with search term" do
      let(:search_term) { "seats" }

      it "filters results by search term" do
        result = subject

        expect(result).to be_success
        expect(result.features).to contain_exactly(feature1)
      end

      context "when search term is blank" do
        let(:search_term) { "" }

        it "returns all features" do
          result = subject

          expect(result).to be_success
          expect(result.features).to contain_exactly(feature1, feature2, feature3)
        end
      end
    end

    context "with filters" do
      let(:filters) { {organization_id: organization.id} }

      it "applies filters" do
        result = subject

        expect(result).to be_success
        expect(result.features).to include(feature1, feature2, feature3)
        expect(result.features).not_to include(other_organization_feature)
      end
    end

    context "when organization has no features" do
      let(:empty_organization) { create(:organization) }

      it "returns empty result" do
        result = described_class.call(organization: empty_organization)

        expect(result).to be_success
        expect(result.features).to be_empty
      end
    end

    context "with a created_at range" do
      let(:filters) { {created_at_from: "2026-03-10T00:00:00Z", created_at_to: "2026-03-20"} }
      let!(:inside_feature) { create(:feature, organization:, created_at: Time.zone.parse("2026-03-20T23:00:00Z")) }

      before do
        create(:feature, organization:, created_at: Time.zone.parse("2026-03-09T23:59:59Z"))
        create(:feature, organization:, created_at: Time.zone.parse("2026-03-21T00:00:00Z"))
      end

      it "returns only the features created inside the range, the date-only upper bound covering its day" do
        expect(subject).to be_success
        expect(subject.features).to eq([inside_feature])
      end
    end

    context "with an invalid created_at_from" do
      let(:filters) { {created_at_from: "not-a-date"} }

      it "fails with invalid_date on the filter" do
        expect(subject).not_to be_success
        expect(subject.error).to be_a(BaseService::ValidationFailure)
        expect(subject.error.messages).to eq(created_at_from: ["invalid_date"])
      end
    end

    context "with cursor pagination" do
      let(:pagination) { CursorPagination::Cursor.new(table: "entitlement_features", limit: 1) }
      let(:discarded_feature) { create(:feature, organization:, created_at: 2.days.from_now) }

      before do
        feature1.update!(created_at: 3.days.ago)
        feature2.update!(created_at: 2.days.ago)
        feature3.update!(created_at: 1.day.ago)
        discarded_feature.discard!
      end

      it "returns the newest feature first, with no order appended after the keyset" do
        expect(subject).to be_success
        expect(subject.features.to_sql).to end_with('ORDER BY "entitlement_features"."created_at" DESC, "entitlement_features"."id" DESC LIMIT 2')

        page = CursorPagination::Page.new(records: subject.features, cursor: pagination)
        expect(page.records).to eq([feature3])
        expect(page.meta[:next_cursor]).to be_present
      end

      it "walks to the next feature with the next cursor" do
        first_page = CursorPagination::Page.new(records: subject.features, cursor: pagination)
        next_cursor = CursorPagination::Cursor.new(table: "entitlement_features", limit: 1, after: first_page.meta[:next_cursor])

        next_result = described_class.call(organization:, pagination: next_cursor)
        next_page = CursorPagination::Page.new(records: next_result.features, cursor: next_cursor)

        expect(next_page.records).to eq([feature2])
      end

      it "never returns a discarded feature or a feature of another organization" do
        cursor = CursorPagination::Cursor.new(table: "entitlement_features", limit: 10)
        records = CursorPagination::Page.new(records: described_class.call(organization:, pagination: cursor).features, cursor:).records

        expect(records).to eq([feature3, feature2, feature1])
      end
    end

    context "with offset pagination on features created at the same time" do
      let(:pagination) { {page: 1, limit: 3} }

      before do
        created_at = 1.day.ago
        [feature1, feature2, feature3].each { it.update!(created_at:) }
      end

      it "orders them by id as a tiebreak" do
        expect(subject).to be_success
        expect(subject.features.to_a).to eq([feature1, feature2, feature3].sort_by(&:id))
      end
    end

    context "with invalid pagination" do
      let(:pagination) { {page: -1, limit: -1} }

      it "still returns a successful result" do
        result = subject

        expect(result).to be_success
        expect(result.features).to be_present
      end
    end
  end
end
