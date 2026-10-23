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

    it "returns the rows after the anchor, excluding it, bounded by one row-value comparison" do
      expect(scope.to_sql).to include(%{ AND (("products"."created_at", "products"."id") < ('})
      expect(scope.to_sql).not_to include(" OR ")
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

  context "with a sort mixing directions" do
    subject(:scope) { described_class.apply(Invoice.where(organization:), cursor) }

    let(:sort) { {issuing_date: :desc, created_at: :desc, id: :asc} }
    let(:cursor) { CursorPagination::Cursor.new(table: "invoices", sort:, limit: 2, **cursor_params) }
    let(:anchor_token) { CursorPagination::Token.encode(table: "invoices", record: anchor, sort:) }
    let(:anchor) { invoices[2] }
    let(:customer) { create(:customer, organization:) }

    # Listed in the expected order: the two in the middle share both the issuing date and
    # the timestamp, so that only the ascending id tells them apart.
    let(:invoices) do
      [
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 28), created_at:),
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 27), created_at: created_at + 1.second),
        *create_list(:invoice, 2, customer:, issuing_date: Date.new(2026, 9, 27), created_at:).sort_by(&:id),
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 26), created_at: created_at + 1.day)
      ]
    end

    before { invoices }

    it "orders the first page on the sort" do
      expect(scope.to_sql).to end_with(%(ORDER BY "invoices"."issuing_date" DESC, "invoices"."created_at" DESC, "invoices"."id" ASC LIMIT 3))
      expect(scope.to_a).to eq(invoices.first(3))
    end

    context "with an after cursor" do
      let(:cursor_params) { {after: anchor_token} }

      it "bounds the page with the expansion of the sort, the leading column bounded on its own" do
        expect(scope.to_sql).to include(
          %{"invoices"."issuing_date" <= '2026-09-27' AND (("invoices"."issuing_date" < '2026-09-27') OR ("invoices"."issuing_date" = '2026-09-27' AND "invoices"."created_at" < '}
        )
        expect(scope.to_sql).to include(%{AND "invoices"."id" > '#{anchor.id}'))})
        expect(scope.to_a).to eq(invoices[3..])
      end
    end

    context "with a before cursor" do
      let(:cursor_params) { {before: anchor_token} }

      it "inverts every direction and returns the rows before the anchor, closest first" do
        expect(scope.to_sql).to include(%("invoices"."issuing_date" >= '2026-09-27' AND ))
        expect(scope.to_sql).to include(%{AND "invoices"."id" < '#{anchor.id}'))})
        expect(scope.to_sql).to end_with(%(ORDER BY "invoices"."issuing_date" ASC, "invoices"."created_at" ASC, "invoices"."id" DESC LIMIT 3))
        expect(scope.to_a).to eq(invoices[0..1].reverse)
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
