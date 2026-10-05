# frozen_string_literal: true

require "rails_helper"

RSpec.describe CursorPagination::Page do
  subject(:page) { fetch(cursor_params) }

  let(:organization) { create(:organization) }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  let(:cursor_params) { {} }

  # Listed in the expected order. Rows share timestamps so that pages break on ties.
  let(:products) do
    [0, 0, 1, 1, 1, 2]
      .map { |offset| create(:product, organization:, created_at: created_at - offset.seconds) }
      .sort { |a, b| [b.created_at, b.id] <=> [a.created_at, a.id] }
  end

  before { products }

  def fetch(params)
    cursor = CursorPagination::Cursor.new(table: "products", limit: 2, **params)
    described_class.new(records: CursorPagination::Keyset.apply(Product.where(organization:), cursor), cursor:)
  end

  def token(record)
    CursorPagination::Token.encode(table: "products", record:)
  end

  context "with the first page" do
    it "returns the first rows and a next cursor only" do
      expect(page.records).to eq(products[0..1])
      expect(page.meta).to eq(next_cursor: token(products[1]), prev_cursor: nil)
    end
  end

  context "with a forward page in the middle" do
    let(:cursor_params) { {after: token(products[1])} }

    it "returns both cursors" do
      expect(page.records).to eq(products[2..3])
      expect(page.meta).to eq(next_cursor: token(products[3]), prev_cursor: token(products[2]))
    end
  end

  context "with the last forward page" do
    let(:cursor_params) { {after: token(products[3])} }

    it "returns no next cursor" do
      expect(page.records).to eq(products[4..5])
      expect(page.meta).to eq(next_cursor: nil, prev_cursor: token(products[4]))
    end
  end

  context "with a backward page in the middle" do
    let(:cursor_params) { {before: token(products[4])} }

    it "returns the rows in list order with both cursors" do
      expect(page.records).to eq(products[2..3])
      expect(page.meta).to eq(next_cursor: token(products[3]), prev_cursor: token(products[2]))
    end
  end

  context "with the first backward page" do
    let(:cursor_params) { {before: token(products[2])} }

    it "returns no prev cursor" do
      expect(page.records).to eq(products[0..1])
      expect(page.meta).to eq(next_cursor: token(products[1]), prev_cursor: nil)
    end
  end

  context "with an empty forward page" do
    let(:cursor_params) { {after: token(products[5])} }

    it "echoes the incoming cursor as the prev cursor" do
      expect(page.records).to be_empty
      expect(page.meta).to eq(next_cursor: nil, prev_cursor: token(products[5]))
    end
  end

  context "with an empty backward page" do
    let(:cursor_params) { {before: token(products[0])} }

    it "echoes the incoming cursor as the next cursor" do
      expect(page.records).to be_empty
      expect(page.meta).to eq(next_cursor: token(products[0]), prev_cursor: nil)
    end
  end

  context "when the query orders after the keyset" do
    subject(:page) do
      cursor = CursorPagination::Cursor.new(table: "products", limit: 2)
      described_class.new(records: CursorPagination::Keyset.apply(Product.where(organization:), cursor).order(:name), cursor:)
    end

    it "refuses to read a page the cursors would not walk" do
      expect { page.records }.to raise_error(ArgumentError, /ordered after its keyset/)
    end
  end

  context "when the anchor row was deleted" do
    let(:cursor_params) { {after: token(products[1])} }

    before { products[1].discard! }

    it "resumes right after its position" do
      expect(page.records).to eq(products[2..3])
    end
  end

  context "with a total count" do
    let(:cursor_params) { {include_total_count: true} }

    before { allow(CursorPagination::TotalCount).to receive(:call).and_call_original }

    it "counts the page's own relation, with the same filters" do
      expect(page.meta).to eq(next_cursor: token(products[1]), prev_cursor: nil, total_count: 6)
    end

    it "counts once however often the meta is read" do
      page.meta
      page.meta

      expect(CursorPagination::TotalCount).to have_received(:call).once
    end
  end

  context "with an estimated total count" do
    let(:cursor_params) { {include_total_count: true} }

    before do
      allow(CursorPagination::TotalCount).to receive(:call)
        .and_return(CursorPagination::TotalCount::Result.new(value: 10_500, outcome: :capped))
    end

    it "flags the total as estimated" do
      expect(page.meta).to include(total_count: 10_500, total_count_estimated: true)
    end
  end

  context "with an estimated total count below the rows already seen" do
    let(:cursor_params) { {include_total_count: true} }

    before do
      allow(CursorPagination::TotalCount).to receive(:call)
        .and_return(CursorPagination::TotalCount::Result.new(value: 1, outcome: :timed_out))
    end

    it "reports at least the rows of the page and the one past it" do
      expect(page.meta).to include(total_count: 3, total_count_estimated: true)
    end
  end

  context "with a total count asked on a later page" do
    subject(:page) { described_class.new(records: Product.where(organization:).reorder(created_at: :desc, id: :desc).limit(3), cursor:) }

    let(:cursor) { CursorPagination::Cursor.new(table: "products", limit: 2, include_total_count: true) }

    # `Cursor` already refuses it: the guard keeps `Page` from counting a page bounded by
    # a cursor, should that rule ever be relaxed.
    before { allow(cursor).to receive(:direction).and_return(:forward) }

    it "refuses to count" do
      expect { page.meta }.to raise_error(ArgumentError, /first page/)
    end
  end

  describe "walking the whole list" do
    it "follows the sort of the cursor, here ascending" do
      sort = {created_at: :asc, id: :asc}
      walked = []
      current = fetch(sort:)
      loop do
        walked.concat(current.records)
        break unless current.meta[:next_cursor]

        current = fetch(sort:, after: current.meta[:next_cursor])
      end

      expect(walked).to eq(products.reverse)
    end

    it "returns every row exactly once, forward then backward" do
      forward = []
      current = fetch({})
      loop do
        forward.concat(current.records)
        break unless current.meta[:next_cursor]

        current = fetch(after: current.meta[:next_cursor])
      end

      backward = []
      loop do
        backward.unshift(*current.records)
        break unless current.meta[:prev_cursor]

        current = fetch(before: current.meta[:prev_cursor])
      end

      expect(forward).to eq(products)
      expect(backward).to eq(products)
    end

    it "keeps every row that existed throughout despite inserts and deletes between pages" do
      first = fetch({})
      next_cursor = first.meta[:next_cursor]
      create(:product, organization:, created_at: created_at + 1.hour)
      products[3].discard!
      second = fetch(after: next_cursor)
      third = fetch(after: second.meta[:next_cursor])

      expect(first.records + second.records + third.records).to eq(products - [products[3]])
      expect(third.meta[:next_cursor]).to be_nil
    end
  end
end
