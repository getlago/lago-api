# frozen_string_literal: true

require "rails_helper"

# Keyset pagination is only correct when the tuple is the whole ordering of the query:
# a query ordering or filtering after `paginate` would break it silently. Each query
# serving a cursor-paginated v2 list is checked twice:
# - with every filter it supports, for the ordering and to run it;
# - as its endpoint calls it by default, for the index serving the page.
RSpec.describe "Cursor-paginated queries" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }

  shared_examples "a keyset-paginated query" do |table:, index:|
    let(:anchor_token) { CursorPagination::Token.encode(table:, record: Struct.new(:id, :created_at).new(SecureRandom.uuid, Time.current)) }

    it "ends with the keyset ordering and runs" do
      scope = filtered_scope.call(CursorPagination::Cursor.new(table:))

      expect(scope.to_sql).to end_with(%(ORDER BY "#{table}"."created_at" DESC, "#{table}"."id" DESC LIMIT 21))
      expect(scope.to_a).to eq([])
    end

    context "when the planner can only use an index already in the tuple order" do
      # Scoped to the transaction wrapping the example. The test tables are nearly empty,
      # so the costs would not tell the indexes apart: without scans nor sorts, only an
      # index serving both the bound and the order is left. The plan tells that the index
      # CAN serve the page, not that the planner will prefer it on production data.
      before do
        %w[enable_seqscan enable_bitmapscan enable_sort].each do |setting|
          ActiveRecord::Base.connection.execute("SET LOCAL #{setting} = off")
        end
      end

      it "serves the first page and the following ones from the cursor index" do
        {
          CursorPagination::Cursor.new(table:) => "Index Scan",
          CursorPagination::Cursor.new(table:, after: anchor_token) => "Index Scan",
          # Paging backward walks the same index in reverse.
          CursorPagination::Cursor.new(table:, before: anchor_token) => "Index Scan Backward"
        }.each do |cursor, scan|
          plan = ActiveRecord::Base.connection.select_rows("EXPLAIN #{default_scope.call(cursor).to_sql}").flatten.join("\n")

          expect(plan).to include("#{scan} using #{index} on #{table}")
        end
      end
    end
  end

  context "with ProductsQuery" do
    let(:product_category) { create(:product_category, organization:) }
    let(:filtered_scope) do
      lambda do |pagination|
        ProductsQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {product_category_ids: [product_category.id], without_product_category: true, product_type: "fixed"}
        ).products
      end
    end
    let(:default_scope) { ->(pagination) { ProductsQuery.call(organization:, pagination:).products } }

    it_behaves_like "a keyset-paginated query", table: "products", index: "index_products_by_cursor"
  end
end
