# frozen_string_literal: true

require "rails_helper"

# Keyset pagination is only correct when the tuple is the whole ordering of the query:
# a query ordering or filtering after `paginate` would break it silently. Each query
# serving a cursor-paginated v2 list is checked twice:
# - with every filter it supports, for the ordering and to run it;
# - as its endpoint calls it by default, for the index serving the page.
RSpec.describe "Cursor-paginated queries" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }

  # Without `index`, only the ordering is checked: for a query several indexes can serve.
  # `sort` is the one the endpoint declares.
  shared_examples "a keyset-paginated query" do |table:, index: nil, sort: CursorPagination::DEFAULT_SORT|
    let(:anchor_token) do
      anchor = Struct.new(:id, :created_at, :issuing_date).new(SecureRandom.uuid, Time.current, Date.current)
      CursorPagination::Token.encode(table:, record: anchor, sort:)
    end
    let(:keyset_order) { sort.map { |column, direction| %("#{table}"."#{column}" #{direction.upcase}) }.join(", ") }

    it "ends with the keyset ordering and runs" do
      scope = filtered_scope.call(CursorPagination::Cursor.new(table:, sort:))

      expect(scope.to_sql).to end_with("ORDER BY #{keyset_order} LIMIT 21")
      expect(scope.to_a).to eq([])
    end

    if index
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
            CursorPagination::Cursor.new(table:, sort:) => "Index Scan",
            CursorPagination::Cursor.new(table:, sort:, after: anchor_token) => "Index Scan",
            # Paging backward walks the same index in reverse.
            CursorPagination::Cursor.new(table:, sort:, before: anchor_token) => "Index Scan Backward"
          }.each do |cursor, scan|
            plan = ActiveRecord::Base.connection.select_rows("EXPLAIN #{default_scope.call(cursor).to_sql}").flatten.join("\n")

            expect(plan).to include("#{scan} using #{index} on #{table}")
          end
        end
      end
    end
  end

  context "with BillingEntitiesQuery" do
    let(:organization) { create(:organization, billing_entities: []) }
    let(:filtered_scope) { ->(pagination) { BillingEntitiesQuery.call(organization:, pagination:).billing_entities } }

    it_behaves_like "a keyset-paginated query", table: "billing_entities"
  end

  context "with CustomersQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        CustomersQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {
            external_id: "customer",
            account_type: ["customer"],
            billing_entity_ids: [organization.default_billing_entity.id],
            countries: ["FR"],
            states: ["Paris"],
            zipcodes: ["75001"],
            currencies: ["EUR"],
            has_tax_identification_number: true,
            customer_type: "individual",
            metadata: {region: "eu"}
          }
        ).customers
      end
    end

    it_behaves_like "a keyset-paginated query", table: "customers"
  end

  context "with PaymentMethodsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        PaymentMethodsQuery.call(
          organization:,
          pagination:,
          filters: {external_customer_id: "customer", payment_provider_customer_id: SecureRandom.uuid, with_deleted: true}
        ).payment_methods
      end
    end

    it_behaves_like "a keyset-paginated query", table: "payment_methods"
  end

  context "with PaymentRequestsQuery" do
    let(:default_scope) { ->(pagination) { PaymentRequestsQuery.call(organization:, pagination:).payment_requests } }

    let(:filtered_scope) do
      lambda do |pagination|
        PaymentRequestsQuery.call(
          organization:,
          pagination:,
          filters: {external_customer_id: "customer", payment_status: "pending", currency: "EUR", billing_entity_ids: [SecureRandom.uuid]}
        ).payment_requests
      end
    end

    it_behaves_like "a keyset-paginated query", table: "payment_requests", index: "index_payment_requests_by_cursor"
  end

  context "with PaymentsQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        PaymentsQuery.call(
          organization:,
          pagination:,
          search_term: "pay",
          filters: {invoice_id: SecureRandom.uuid, external_customer_id: "customer", currency: "EUR"}
        ).payments
      end
    end

    it_behaves_like "a keyset-paginated query", table: "payments"
  end

  context "with TaxesQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        TaxesQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          order: "rate",
          filters: {auto_generated: true, applied_to_organization: false}
        ).taxes
      end
    end
    let(:default_scope) { ->(pagination) { TaxesQuery.call(organization:, pagination:).taxes } }

    it_behaves_like "a keyset-paginated query", table: "taxes", index: "index_taxes_by_cursor"
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

    # No index for the default single status: both cursor indexes serve it in order, at the
    # same cost on the near-empty test table, so the planner's pick is arbitrary.
    it_behaves_like "a keyset-paginated query", table: "contracts"

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

  context "with ProductFeesQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        ProductFeesQuery.call(
          organization:,
          pagination:,
          filters: {
            payment_status: "succeeded",
            external_customer_id: "customer",
            external_contract_id: "contract",
            currency: "eur",
            event_transaction_id: "transaction",
            created_at_from: "2026-01-01",
            created_at_to: "2026-12-31",
            succeeded_at_from: "2026-01-01",
            succeeded_at_to: "2026-12-31",
            failed_at_from: "2026-01-01",
            failed_at_to: "2026-12-31",
            refunded_at_from: "2026-01-01",
            refunded_at_to: "2026-12-31"
          }
        ).fees
      end
    end
    let(:default_scope) { ->(pagination) { ProductFeesQuery.call(organization:, pagination:).fees } }

    it_behaves_like "a keyset-paginated query", table: "fees", index: "index_fees_by_product_cursor"
  end

  context "with InvoicesQuery" do
    let(:filtered_scope) do
      lambda do |pagination|
        InvoicesQuery.call(
          organization:,
          search_term: "a",
          pagination:,
          filters: {
            amount_from: 1,
            amount_to: 2,
            billing_entity_ids: [SecureRandom.uuid],
            currency: "EUR",
            customer_id: SecureRandom.uuid,
            invoice_type: "contract",
            issuing_date_from: "2026-01-01",
            issuing_date_to: "2026-12-31",
            partially_paid: false,
            payment_dispute_lost: false,
            payment_overdue: false,
            payment_status: ["pending"],
            product_catalog: true,
            purchase_order_number: "po",
            settlements: ["credit_note"],
            status: ["finalized"]
          }
        ).invoices
      end
    end
    let(:default_scope) { ->(pagination) { InvoicesQuery.call(organization:, pagination:, filters: {product_catalog: true}).invoices } }

    # The order of the v1 lists: the index mixes directions, so the pages are bounded by
    # an OR-expansion, which the index serves from its leading column.
    it_behaves_like "a keyset-paginated query", table: "invoices", index: "index_invoices_by_cursor", sort: Api::V2::InvoiceIndex::SORT
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
end
