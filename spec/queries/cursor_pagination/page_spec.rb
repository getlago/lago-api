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
