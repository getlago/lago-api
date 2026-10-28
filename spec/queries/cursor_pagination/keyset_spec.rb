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

    it "binds the anchor time with sub-second precision, not truncated to the second" do
      expect(scope.to_sql).to include("10:00:01.000001")
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

  context "with a sort on the issuing date" do
    subject(:scope) { described_class.apply(Invoice.where(organization:), cursor) }

    let(:sort) { {issuing_date: :desc, created_at: :desc, id: :desc} }
    let(:cursor) { CursorPagination::Cursor.new(table: "invoices", sort:, limit: 2, **cursor_params) }
    let(:anchor_token) { CursorPagination::Token.encode(table: "invoices", record: anchor, sort:) }
    let(:anchor) { invoices[2] }
    let(:customer) { create(:customer, organization:) }

    # Listed in the expected order: the two in the middle share both the issuing date and
    # the timestamp, so that only the id tells them apart.
    let(:invoices) do
      [
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 28), created_at:),
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 27), created_at: created_at + 1.second),
        *create_list(:invoice, 2, customer:, issuing_date: Date.new(2026, 9, 27), created_at:).sort_by(&:id).reverse,
        create(:invoice, customer:, issuing_date: Date.new(2026, 9, 26), created_at: created_at + 1.day)
      ]
    end

    before { invoices }

    it "orders the first page on the sort" do
      expect(scope.to_sql).to end_with(%(ORDER BY "invoices"."issuing_date" DESC, "invoices"."created_at" DESC, "invoices"."id" DESC LIMIT 3))
      expect(scope.to_a).to eq(invoices.first(3))
    end

    context "with an after cursor" do
      let(:cursor_params) { {after: anchor_token} }

      it "bounds the page with one row-value comparison over the three columns" do
        expect(scope.to_sql).to include(%{("invoices"."issuing_date", "invoices"."created_at", "invoices"."id") < ('2026-09-27', })
        expect(scope.to_a).to eq(invoices[3..])
      end
    end

    context "with a before cursor" do
      let(:cursor_params) { {before: anchor_token} }

      it "returns the rows before the anchor, closest first" do
        expect(scope.to_sql).to include(%{("invoices"."issuing_date", "invoices"."created_at", "invoices"."id") > ('2026-09-27', })
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

  # A ClickHouse log list sorts on a time column and a string business id, with no `id`
  # column: the keyset must bind the same tuple on these columns and reverse it backward.
  context "with a time column and a string tiebreak", clickhouse: true do
    subject(:scope) { described_class.apply(base_scope, cursor) }

    let(:base_scope) { Clickhouse::ActivityLog.where(organization:) }
    let(:sort) { {logged_at: :desc, activity_id: :desc} }
    let(:cursor) { CursorPagination::Cursor.new(table: "activity_logs", sort:, limit: 2, **cursor_params) }
    let(:cursor_params) { {} }
    let(:anchor) { Struct.new(:logged_at, :activity_id).new(Time.current, "evt_not-a-uuid_42") }
    let(:anchor_token) { CursorPagination::Token.encode(table: "activity_logs", record: anchor, sort:) }

    context "without cursor" do
      it "orders the first page on the tuple" do
        expect(scope.to_sql).to end_with("ORDER BY activity_logs.logged_at DESC, activity_logs.activity_id DESC LIMIT 3")
      end
    end

    context "with an after cursor" do
      let(:cursor_params) { {after: anchor_token} }

      it "bounds the page with the descending tuple comparison" do
        expect(scope.to_sql).to include("(activity_logs.logged_at, activity_logs.activity_id) < ")
        expect(scope.to_sql).to include("'evt_not-a-uuid_42'")
      end
    end

    context "with a before cursor" do
      let(:cursor_params) { {before: anchor_token} }

      it "reverses the tuple and the order" do
        expect(scope.to_sql).to include("(activity_logs.logged_at, activity_logs.activity_id) > ")
        expect(scope.to_sql).to end_with("ORDER BY activity_logs.logged_at ASC, activity_logs.activity_id ASC LIMIT 3")
      end
    end
  end
end
