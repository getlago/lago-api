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

  context "with ProductCategoriesQuery" do
    let(:filtered_scope) do
      ->(pagination) { ProductCategoriesQuery.call(organization:, search_term: "a", pagination:).product_categories }
    end
    let(:default_scope) { ->(pagination) { ProductCategoriesQuery.call(organization:, pagination:).product_categories } }

    it_behaves_like "a keyset-paginated query", table: "product_categories", index: "index_product_categories_by_cursor"
  end

  context "with RateCardsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        RateCardsQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {
            product_ids: [SecureRandom.uuid],
            product_filter_ids: [SecureRandom.uuid],
            product_category_ids: [SecureRandom.uuid],
            without_product_category: true,
            code: "code",
            product_code: "product",
            product_filter_code: "filter"
          }
        ).rate_cards
      end
    end
    let(:default_scope) { ->(pagination) { RateCardsQuery.call(organization:, pagination:).rate_cards } }

    it_behaves_like "a keyset-paginated query", table: "rate_cards", index: "index_rate_cards_by_cursor"
  end

  context "with CatalogPlansQuery" do
    let(:filtered_scope) { ->(pagination) { CatalogPlansQuery.call(organization:, search_term: "a", pagination:).catalog_plans } }
    let(:default_scope) { ->(pagination) { CatalogPlansQuery.call(organization:, pagination:).catalog_plans } }

    it_behaves_like "a keyset-paginated query", table: "catalog_plans", index: "index_catalog_plans_by_cursor"
  end

  context "with ContractsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        ContractsQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {
            external_customer_id: "customer",
            plan_code: "plan",
            status: ["active"],
            billing_entity_ids: [SecureRandom.uuid],
            has_rate_overrides: "true"
          }
        ).contracts
      end
    end
    # The endpoint always filters on a status, active by default.
    let(:default_scope) do
      ->(pagination) { ContractsQuery.call(organization:, pagination:, filters: {status: ["active"]}).contracts }
    end

    # A single status, the default: `status` comes right after the organization in the index.
    it_behaves_like "a keyset-paginated query", table: "contracts", index: "index_contracts_by_status_cursor"

    context "when asked for several statuses" do
      let(:scope) do
        ContractsQuery.call(organization:, pagination: CursorPagination::Cursor.new(table: "contracts"), filters: {status: %w[active pending]}).contracts
      end

      before do
        %w[enable_seqscan enable_bitmapscan enable_sort].each do |setting|
          ActiveRecord::Base.connection.execute("SET LOCAL #{setting} = off")
        end
      end

      # The status index cannot return several statuses in order: the status-free one does.
      it "serves the page in order from the status-free cursor index" do
        plan = ActiveRecord::Base.connection.select_rows("EXPLAIN #{scope.to_sql}").flatten.join("\n")

        expect(plan).to include("Index Scan using index_contracts_by_cursor on contracts")
      end
    end
  end

  context "with ProductFiltersQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        ProductFiltersQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {product_id: SecureRandom.uuid, product_category_ids: [SecureRandom.uuid], without_product_category: true}
        ).product_filters
      end
    end
    let(:default_scope) do
      ->(pagination) { ProductFiltersQuery.call(organization:, pagination:, filters: {product_id: SecureRandom.uuid}).product_filters }
    end

    it_behaves_like "a keyset-paginated query", table: "product_filters", index: "index_product_filters_by_cursor"

    # The default scope of the model orders ascending: the keyset must replace it.
    it "drops the ordering of the default scope" do
      expect(filtered_scope.call(CursorPagination::Cursor.new(table: "product_filters")).to_sql).not_to include("ASC")
    end
  end

  context "with PlanRateCardsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        PlanRateCardsQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {plan_id: SecureRandom.uuid, product_category_ids: [SecureRandom.uuid], has_rate_overrides: true}
        ).plan_rate_cards
      end
    end
    let(:default_scope) do
      ->(pagination) { PlanRateCardsQuery.call(organization:, pagination:, filters: {plan_id: SecureRandom.uuid}).plan_rate_cards }
    end

    it_behaves_like "a keyset-paginated query", table: "plan_rate_cards", index: "index_plan_rate_cards_by_cursor"
  end

  context "with ContractRateCardsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        ContractRateCardsQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {contract_id: SecureRandom.uuid, product_category_ids: [SecureRandom.uuid], has_rate_overrides: true}
        ).contract_rate_cards
      end
    end
    let(:default_scope) do
      lambda do |pagination|
        ContractRateCardsQuery.call(organization:, pagination:, filters: {contract_id: SecureRandom.uuid}).contract_rate_cards
      end
    end

    it_behaves_like "a keyset-paginated query", table: "contract_rate_cards", index: "index_contract_rate_cards_by_cursor"
  end

  # Joined to the taxes, to leave out the discarded ones: the cursor index serves the links,
  # the outer side of the join.
  context "with RateCardTaxesQuery" do
    let(:filtered_scope) do
      ->(pagination) { RateCardTaxesQuery.call(organization:, pagination:, filters: {rate_card_id: SecureRandom.uuid}).applied_taxes }
    end
    # The endpoint always passes the only filter.
    let(:default_scope) { filtered_scope }

    it_behaves_like "a keyset-paginated query", table: "rate_cards_taxes", index: "index_rate_cards_taxes_by_cursor"
  end
end
