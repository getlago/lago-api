# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination::Keyset do
  subject(:scope) { described_class.apply(base_scope, cursor) }

  let(:organization) { create(:organization) }
  let(:base_scope) { Product.where(organization:).order(:name) }
  let(:cursor) { CursorPagination::Cursor.new(table: "products", limit: 2, **cursor_params) }
  let(:cursor_params) { {} }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  let(:anchor) { products[2] }
  let(:anchor_token) { CursorPagination::Token.encode(table: "products", record: anchor) }

  # Five products, the three in the middle sharing the same timestamp, listed in the
  # expected order: created_at DESC, then id DESC.
  let(:products) do
    [
      create(:product, organization:, created_at: created_at + 2.seconds),
      *create_list(:product, 3, organization:, created_at: created_at + 1.second).sort_by(&:id).reverse,
      create(:product, organization:, created_at:)
    ]
  end

  before { products }

  context "without cursor" do
    it "replaces the ordering with the tuple and fetches one extra row" do
      expect(scope.to_sql).to end_with(%(ORDER BY "products"."created_at" DESC, "products"."id" DESC LIMIT 3))
      expect(scope.to_a).to eq(products.first(3))
    end
  end

  context "with an after cursor" do
    let(:cursor_params) { {after: anchor_token} }

    it "returns the rows after the anchor, excluding it" do
      expect(scope.to_sql).to include(%{("products"."created_at", "products"."id") < })
      expect(scope.to_a).to eq(products[3..])
    end
  end

  context "with a before cursor" do
    let(:cursor_params) { {before: anchor_token} }

    it "returns the rows before the anchor, closest first" do
      expect(scope.to_sql).to end_with(%(ORDER BY "products"."created_at" ASC, "products"."id" ASC LIMIT 3))
      expect(scope.to_a).to eq(products[0..1].reverse)
    end
  end

  context "with an ascending sort" do
    let(:sort) { {created_at: :asc, id: :asc} }
    let(:cursor) { CursorPagination::Cursor.new(table: "products", sort:, limit: 2, **cursor_params) }
    let(:anchor_token) { CursorPagination::Token.encode(table: "products", record: anchor, sort:) }
    let(:ascending) { products.reverse }

    it "orders the first page ascending" do
      expect(scope.to_sql).to end_with(%(ORDER BY "products"."created_at" ASC, "products"."id" ASC LIMIT 3))
      expect(scope.to_a).to eq(ascending.first(3))
    end

    context "with an after cursor" do
      let(:cursor_params) { {after: anchor_token} }

      it "returns the rows after the anchor, excluding it" do
        expect(scope.to_sql).to include(%{("products"."created_at", "products"."id") > })
        expect(scope.to_a).to eq(ascending[3..])
      end
    end

    context "with a before cursor" do
      let(:cursor_params) { {before: anchor_token} }

      it "returns the rows before the anchor, closest first" do
        expect(scope.to_sql).to end_with(%(ORDER BY "products"."created_at" DESC, "products"."id" DESC LIMIT 3))
        expect(scope.to_a).to eq(ascending[0..1].reverse)
      end
    end
  end

  context "when the cursor was built for another table" do
    let(:cursor) { CursorPagination::Cursor.new(table: "product_categories") }

    it "raises an argument error" do
      expect { scope }.to raise_error(ArgumentError, /product_categories applied to products/)
    end
  end
end
