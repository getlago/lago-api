# frozen_string_literal: true

# Development only: seeds 100,000 payments in a separate organization, then
# records EXPLAIN ANALYZE for the combined filter and its pagination count.
#   bundle exec rails runner script/benchmark_payments_filters.rb
raise "This benchmark is only for development" unless Rails.env.development?

require "factory_bot_rails"
FactoryBot.find_definitions if FactoryBot.factories.none?
ActiveJob::Base.queue_adapter = :test

organization = Organization.find_by(slug: "payments-filters-benchmark")
connection = ApplicationRecord.connection
unless organization
  Organization.transaction do
    organization = FactoryBot.create(:organization, slug: "payments-filters-benchmark", name: "Payments benchmark", webhook_url: nil)
    customer = FactoryBot.create(:customer, organization:)
    provider = FactoryBot.create(:stripe_provider, organization:)
    provider_customer = FactoryBot.create(:stripe_customer, organization:, customer:, payment_provider: provider)
    method = FactoryBot.create(:payment_method, organization:, customer:, payment_provider: provider,
      payment_provider_customer: provider_customer, provider_method_type: "card")
    values = {org: organization.id, customer: customer.id, billing_entity: organization.default_billing_entity.id,
              provider: provider.id, provider_customer: provider_customer.id, method: method.id}

    connection.execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL, values]))
      CREATE TEMP TABLE payments_filter_rows ON COMMIT DROP AS
        SELECT n, gen_random_uuid() AS invoice_id, gen_random_uuid() AS second_invoice_id,
          CASE WHEN n % 5 = 0 THEN gen_random_uuid() END AS request_id,
          timestamp '2026-08-01 12:00:00' + (n % 60) * interval '1 day' AS created_at
        FROM generate_series(1, 100000) AS n;

      INSERT INTO invoices (id, organization_id, customer_id, billing_entity_id, number, status,
        issuing_date, currency, total_amount_cents, created_at, updated_at)
        SELECT invoice_id, :org, :customer, :billing_entity, 'PERF-' || lpad(n::text, 6, '0'), 1,
          created_at::date, 'EUR', 10000, created_at, created_at FROM payments_filter_rows;
      INSERT INTO invoices (id, organization_id, customer_id, billing_entity_id, number, status,
        issuing_date, currency, total_amount_cents, created_at, updated_at)
        SELECT second_invoice_id, :org, :customer, :billing_entity, 'PERF-' || lpad(n::text, 6, '0') || '-B', 1,
          created_at::date, 'EUR', 10000, created_at, created_at FROM payments_filter_rows WHERE request_id IS NOT NULL;
      INSERT INTO payment_requests (id, organization_id, customer_id, amount_cents, amount_currency, created_at, updated_at)
        SELECT request_id, :org, :customer, 20000, 'EUR', created_at, created_at
        FROM payments_filter_rows WHERE request_id IS NOT NULL;
      INSERT INTO invoices_payment_requests (invoice_id, payment_request_id, organization_id, created_at, updated_at)
        SELECT invoice_id, request_id, :org::uuid, created_at, created_at FROM payments_filter_rows WHERE request_id IS NOT NULL
        UNION ALL
        SELECT second_invoice_id, request_id, :org::uuid, created_at, created_at FROM payments_filter_rows WHERE request_id IS NOT NULL;
      INSERT INTO payments (organization_id, customer_id, payable_id, payable_type, amount_cents, amount_currency,
        status, payable_payment_status, payment_provider_id, payment_provider_customer_id, payment_method_id,
        provider_payment_method_data, created_at, updated_at)
        SELECT :org, :customer, COALESCE(request_id, invoice_id),
          CASE WHEN request_id IS NULL THEN 'Invoice' ELSE 'PaymentRequest' END,
          n * 100, CASE WHEN n % 3 = 0 THEN 'USD' ELSE 'EUR' END, 'succeeded',
          (ARRAY['pending', 'processing', 'succeeded', 'failed'])[n % 4 + 1]::payment_payable_payment_status,
          :provider, :provider_customer, :method,
          CASE WHEN n % 3 = 0 THEN '{}'::jsonb
            ELSE jsonb_build_object('type', (ARRAY['card', 'sepa_debit', 'us_bank_account', 'bacs_debit',
              'link', 'boleto', 'crypto', 'customer_balance'])[(n - 1) % 8 + 1]) END,
          created_at, created_at FROM payments_filter_rows;
    SQL
  end
end

%w[invoices invoices_payment_requests payment_requests payments payment_methods].each do |table|
  connection.execute("ANALYZE #{table}")
end
filters = {invoice_number: "perf-000035", payment_method_type: %w[card sepa_debit us_bank_account],
           created_at_from: Date.new(2026, 9, 1), created_at_to: Date.new(2026, 9, 7)}
payments = PaymentsQuery.call(organization:, filters:, pagination: {page: 1, limit: 20}).payments
count_sql = payments.except(:limit, :offset, :order).select("COUNT(*)").to_sql
plans = {list: payments.to_sql, count: count_sql}.to_h do |name, sql|
  connection.execute("SET statement_timeout = '30s'")
  plan = connection.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) #{sql}").values.flatten.join("\n")
  [name, {sql:, plan:}]
ensure
  connection.execute("RESET statement_timeout")
end
File.write(Rails.root.join("tmp/payments_filters_explain.json"), JSON.pretty_generate({rows: 100_000, filters:, plans:}))
Rails.logger.info "Benchmark complete. Plans: tmp/payments_filters_explain.json"
