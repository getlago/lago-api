# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination::Cursor do
  subject(:cursor) { described_class.from_params(params, table: "products") }

  let(:params) { {} }
  let(:product) { build_stubbed(:product, created_at: Time.zone.parse("2026-09-28T10:11:12.123456Z")) }
  let(:token) { CursorPagination::Token.encode(table: "products", record: product) }

  shared_examples "a pagination error" do |code, details|
    it "raises #{code}" do
      expect { cursor }.to raise_error(CursorPagination::Error) { |error|
        expect(error.code).to eq(code)
        expect(error.details).to eq(details)
      }
    end
  end

  context "without parameters" do
    it "reads the first page with the default limit and sort" do
      expect(cursor).to have_attributes(table: "products", sort: CursorPagination::DEFAULT_SORT, limit: 20, direction: :first, key: nil)
      expect(cursor).not_to be_include_total_count
    end
  end

  context "with an ascending sort" do
    subject(:cursor) { described_class.from_params(params, table: "products", sort: {created_at: :asc, id: :asc}) }

    it "keeps it" do
      expect(cursor.sort).to eq(created_at: :asc, id: :asc)
    end

    context "with a cursor minted under the default sort" do
      let(:params) { {after: token} }

      it_behaves_like "a pagination error", "pagination_cursor_expired", {after: {reason: "sort_changed"}}
    end
  end

  context "with a sort on other columns" do
    subject(:cursor) { described_class.new(table: "products", sort: {name: :asc, id: :asc}) }

    it "raises an argument error, until cursor keys are typed" do
      expect { cursor }.to raise_error(ArgumentError, /created_at then id/)
    end
  end

  context "with a sort mixing directions" do
    subject(:cursor) { described_class.new(table: "products", sort: {created_at: :desc, id: :asc}) }

    it "raises an argument error" do
      expect { cursor }.to raise_error(ArgumentError, /single direction/)
    end
  end

  context "with a limit as a string" do
    let(:params) { {limit: "100"} }

    it "casts it" do
      expect(cursor.limit).to eq(100)
    end
  end

  context "with a limit as an integer" do
    let(:params) { {limit: 1} }

    it "keeps it" do
      expect(cursor.limit).to eq(1)
    end
  end

  context "with an empty limit" do
    let(:params) { {limit: ""} }

    it "uses the default limit" do
      expect(cursor.limit).to eq(20)
    end
  end

  context "with a limit of 0" do
    let(:params) { {limit: "0"} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {value: "0", allowed_range: "1..100"}}
  end

  context "with a limit above the maximum" do
    let(:params) { {limit: "101"} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {value: "101", allowed_range: "1..100"}}
  end

  context "with a non-integer limit" do
    let(:params) { {limit: "1.5"} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {value: "1.5", allowed_range: "1..100"}}
  end

  context "with a negative limit" do
    let(:params) { {limit: "-1"} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {value: "-1", allowed_range: "1..100"}}
  end

  context "with a limit too long to be echoed back" do
    let(:params) { {limit: "1" * 21} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {allowed_range: "1..100"}}
  end

  context "with a limit that is not a string" do
    let(:params) { {limit: ["1"]} }

    it_behaves_like "a pagination error", "invalid_pagination_limit", {limit: {allowed_range: "1..100"}}
  end

  context "with offset pagination parameters" do
    let(:params) { {page: "2", per_page: "50"} }

    it_behaves_like "a pagination error",
      "invalid_pagination_parameter",
      {page: {reason: "replaced_by_cursor"}, per_page: {reason: "replaced_by_cursor"}}
  end

  context "with an offset page only" do
    let(:params) { {page: "1", limit: "10"} }

    it_behaves_like "a pagination error", "invalid_pagination_parameter", {page: {reason: "replaced_by_cursor"}}
  end

  context "with an after cursor" do
    let(:params) { {after: token} }

    it "pages forward from the decoded key" do
      expect(cursor).to have_attributes(direction: :forward, after: token, before: nil, key: [product.created_at.utc, product.id])
    end
  end

  context "with a before cursor" do
    let(:params) { {before: token} }

    it "pages backward from the decoded key" do
      expect(cursor).to have_attributes(direction: :backward, after: nil, before: token, key: [product.created_at.utc, product.id])
      expect(cursor).to be_backward
    end
  end

  context "with an empty cursor" do
    let(:params) { {after: ""} }

    it "reads the first page" do
      expect(cursor.direction).to eq(:first)
    end
  end

  context "with a cursor that is not a string" do
    let(:params) { {after: [token]} }

    it_behaves_like "a pagination error", "invalid_pagination_cursor", {after: {reason: "malformed"}}
  end

  context "with an invalid cursor" do
    let(:params) { {before: "a"} }

    it_behaves_like "a pagination error", "invalid_pagination_cursor", {before: {reason: "malformed"}}
  end

  context "with a cursor minted for another table" do
    let(:token) { CursorPagination::Token.encode(table: "product_categories", record: product) }
    let(:params) { {after: token} }

    it_behaves_like "a pagination error", "invalid_pagination_cursor", {after: {reason: "wrong_resource"}}
  end

  context "with both cursors" do
    let(:params) { {after: token, before: token} }

    it_behaves_like "a pagination error",
      "invalid_pagination_cursor",
      {after: {reason: "exclusive_with_before"}, before: {reason: "exclusive_with_after"}}
  end

  context "with include_total_count on the first page" do
    let(:params) { {include_total_count: "true"} }

    it "requests the count" do
      expect(cursor).to be_include_total_count
    end
  end

  context "with include_total_count set to false on a later page" do
    let(:params) { {include_total_count: "false", after: token} }

    it "does not request the count" do
      expect(cursor).not_to be_include_total_count
    end
  end

  context "with include_total_count that is not a boolean" do
    let(:params) { {include_total_count: "yes"} }

    it_behaves_like "a pagination error",
      "invalid_pagination_parameter",
      {include_total_count: {reason: "not_a_boolean", allowed_values: %w[true false]}}
  end

  context "with include_total_count on a later page" do
    let(:params) { {include_total_count: "true", after: token} }

    it_behaves_like "a pagination error", "total_count_first_page_only", {include_total_count: {reason: "first_page_only"}}
  end
end
