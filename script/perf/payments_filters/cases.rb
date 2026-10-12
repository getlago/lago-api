# frozen_string_literal: true

# Case matrix for the payments list filters performance work. Shared by
# explain.rb (plans) and bench.rb (HTTP load). Values that depend on the data
# (rare currency, p99 amount, an existing receipt number...) are resolved from
# the database at runtime so nothing is hard-coded and the matrix survives a
# regenerated dataset.
module PaymentsFiltersPerf
  module Cases
    module_function

    # Resolves the concrete values the matrix needs for one organization.
    def resolve_values(organization)
      conn = ApplicationRecord.connection
      org_id = conn.quote(organization.id)
      payments = "payments WHERE organization_id = #{org_id}"

      currencies = conn.select_rows("SELECT amount_currency, count(*) FROM #{payments} GROUP BY 1 ORDER BY 2 DESC")
      providers = conn.select_rows(<<~SQL)
        SELECT pp.type, count(*) FROM payments p JOIN payment_providers pp ON pp.id = p.payment_provider_id
        WHERE p.organization_id = #{org_id} GROUP BY 1 ORDER BY 2 DESC
      SQL
      json_types = conn.select_rows(<<~SQL)
        SELECT provider_payment_method_data->>'type', count(*) FROM #{payments}
          AND provider_payment_method_data->>'type' IS NOT NULL GROUP BY 1 ORDER BY 2 DESC
      SQL
      fallback_only = conn.select_value(<<~SQL)
        SELECT pm.provider_method_type FROM payment_methods pm
        WHERE pm.organization_id = #{org_id}
          AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.organization_id = #{org_id} AND p.provider_payment_method_data->>'type' = pm.provider_method_type)
        GROUP BY 1 ORDER BY count(*) DESC LIMIT 1
      SQL
      customers = conn.select_rows(<<~SQL)
        SELECT c.external_id, count(*) FROM payments p JOIN customers c ON c.id = p.customer_id
        WHERE p.organization_id = #{org_id} GROUP BY 1 ORDER BY 2 DESC
      SQL
      amounts = conn.select_one(<<~SQL)
        SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY amount_cents) AS p50,
               percentile_disc(0.99) WITHIN GROUP (ORDER BY amount_cents) AS p99
        FROM #{payments}
      SQL
      max_created = conn.select_value("SELECT max(created_at) FROM #{payments}")
      receipt = conn.select_value("SELECT number FROM payment_receipts WHERE organization_id = #{org_id} ORDER BY created_at DESC OFFSET 1000 LIMIT 1")
      invoice_direct = conn.select_value(<<~SQL)
        SELECT i.number FROM payments p JOIN invoices i ON i.id = p.payable_id
        WHERE p.organization_id = #{org_id} AND p.payable_type = 'Invoice' AND i.status = 1
        ORDER BY p.created_at DESC OFFSET 1000 LIMIT 1
      SQL
      invoice_via_request = conn.select_value(<<~SQL)
        SELECT i.number FROM payments p
        JOIN invoices_payment_requests ipr ON ipr.payment_request_id = p.payable_id
        JOIN invoices i ON i.id = ipr.invoice_id
        WHERE p.organization_id = #{org_id} AND p.payable_type = 'PaymentRequest'
        ORDER BY p.created_at DESC OFFSET 100 LIMIT 1
      SQL
      search_hit = conn.select_value("SELECT provider_payment_id FROM #{payments} AND provider_payment_id IS NOT NULL ORDER BY created_at DESC OFFSET 5000 LIMIT 1")

      {
        common_currency: currencies.first&.first,
        rare_currency: currencies.last&.first,
        common_provider: providers.first&.first,
        rare_provider: providers.last&.first,
        common_method: json_types.first&.first,
        rare_method: json_types.last&.first,
        fallback_method: fallback_only,
        heavy_customer: customers.first&.first,
        light_customer: customers[customers.size / 2]&.first,
        p50_amount: amounts["p50"].to_i,
        p99_amount: amounts["p99"].to_i,
        max_created: max_created,
        receipt_hit: receipt,
        invoice_hit_direct: invoice_direct,
        invoice_hit_request: invoice_via_request,
        search_hit: search_hit&.then { |s| s[-10..] || s }
      }
    end

    # Turns a PaymentProviders::* STI type into the API filter value (stripe, gocardless...).
    def provider_api_name(type)
      type.to_s.delete_prefix("PaymentProviders::").delete_suffix("Provider").underscore
    end

    # Each case: name, filters (PaymentsQuery filter names), search_term, page,
    # selective (true when the case must meet the strict G3/G5 targets: receipt/invoice number,
    # customer, rare status values, rare method type, rare currency, narrow date range, and the
    # combos built from them; `failed` is graded as a common value, see the internal document).
    def matrix(values)
      v = values
      last7_from = (v[:max_created].to_date - 7).iso8601
      last7_to = v[:max_created].to_date.iso8601
      wide_from = (v[:max_created].to_date - 730).iso8601
      common_provider = provider_api_name(v[:common_provider])
      rare_provider = provider_api_name(v[:rare_provider])

      cases = [
        {name: "control", filters: {}, selective: false},
        {name: "control_page50", filters: {}, page: 50, selective: false},

        {name: "status_common_succeeded", filters: {payment_status: ["succeeded"]}, selective: false},
        {name: "status_common_succeeded_page50", filters: {payment_status: ["succeeded"]}, page: 50, selective: false},
        {name: "status_rare_failed", filters: {payment_status: ["failed"]}, selective: false},
        {name: "status_rare_pending", filters: {payment_status: ["pending"]}, selective: true},
        {name: "status_rare_processing", filters: {payment_status: ["processing"]}, selective: true},
        {name: "status_rare_pending_processing", filters: {payment_status: %w[pending processing]}, selective: true},

        # amount is a continuous range, not in the G5 list of selective cases: its counts are graded
        # with the non-selective bucket and reported separately.
        {name: "amount_common_from_p50", filters: {amount_from: v[:p50_amount]}, selective: false},
        {name: "amount_rare_from_p99", filters: {amount_from: v[:p99_amount]}, selective: false},
        {name: "amount_rare_range", filters: {amount_from: v[:p99_amount], amount_to: v[:p99_amount] * 2}, selective: false},

        {name: "created_7d", filters: {created_at_from: last7_from, created_at_to: last7_to}, selective: true},
        {name: "created_24m", filters: {created_at_from: wide_from, created_at_to: last7_to}, selective: false},

        {name: "currency_common", filters: {currency: v[:common_currency]}, selective: false},
        {name: "currency_rare", filters: {currency: v[:rare_currency]}, selective: true},

        {name: "provider_common", filters: {payment_provider_type: [common_provider]}, selective: false},
        # the second provider carries ~15 % of the payments here: a common value, not a selective one
        {name: "provider_rare", filters: {payment_provider_type: [rare_provider]}, selective: false},
        {name: "provider_miss", filters: {payment_provider_type: ["cashfree"]}, selective: true},
        # payment_method_type cases were removed with the filter (baseline evidence stays under plans/baseline).

        {name: "receipt_hit", filters: {receipt_number: v[:receipt_hit]&.downcase}, selective: true},
        {name: "receipt_miss", filters: {receipt_number: "PERF-NOPE-RCPT-000001"}, selective: true},

        {name: "invoice_hit_direct", filters: {invoice_number: v[:invoice_hit_direct]&.downcase}, selective: true},
        {name: "invoice_hit_request", filters: {invoice_number: v[:invoice_hit_request]&.downcase}, selective: true},
        {name: "invoice_miss", filters: {invoice_number: "PERF-NOPE-000000-000000001"}, selective: true},

        {name: "customer_heavy", filters: {external_customer_id: v[:heavy_customer]}, selective: true},
        {name: "customer_light", filters: {external_customer_id: v[:light_customer]}, selective: true},

        {name: "payment_type_manual", filters: {payment_type: ["manual"]}, selective: false},
        {name: "payment_type_provider", filters: {payment_type: ["provider"]}, selective: false},
        {name: "payable_type_request", filters: {payable_type: ["PaymentRequest"]}, selective: false},
        {name: "payable_type_invoice", filters: {payable_type: ["Invoice"]}, selective: false},

        {name: "search_term", filters: {}, search_term: v[:search_hit], selective: true},
        {name: "search_term_status", filters: {payment_status: ["succeeded"]}, search_term: v[:search_hit], selective: true},

        {name: "combo_status_currency_date", filters: {payment_status: ["succeeded"], currency: v[:common_currency], created_at_from: last7_from, created_at_to: last7_to}, selective: true},
        {name: "combo_status_amount", filters: {payment_status: ["failed"], amount_from: v[:p50_amount]}, selective: false},
        {name: "combo_customer_status_date", filters: {external_customer_id: v[:heavy_customer], payment_status: ["succeeded"], created_at_from: wide_from, created_at_to: last7_to}, selective: true},
        {name: "combo_provider_status", filters: {payment_provider_type: [common_provider], payment_status: ["failed"]}, selective: false},
        {name: "five_filter_common", filters: {payment_status: ["succeeded"], currency: v[:common_currency], created_at_from: wide_from, created_at_to: last7_to, amount_from: 100, payment_provider_type: [common_provider]}, selective: false},
        {name: "five_filter_rare", filters: {payment_status: ["failed"], currency: v[:rare_currency], created_at_from: last7_from, created_at_to: last7_to, amount_from: v[:p50_amount], payment_provider_type: [rare_provider]}, selective: true}
      ]

      unresolved, usable = cases.partition { |c| c[:filters].values.flatten.any?(&:nil?) }
      warn "skipping cases with unresolved values: #{unresolved.map { |c| c[:name] }.join(", ")}" if unresolved.any?
      usable.map { |c| {page: 1, search_term: nil}.merge(c) }
    end

    # Query string for GET /api/v1/payments, mirroring PaymentIndex's parameter names.
    def to_query_params(kase)
      params = {"per_page" => 20, "page" => kase[:page]}
      params["search_term"] = kase[:search_term] if kase[:search_term]
      kase[:filters].each do |key, value|
        if value.is_a?(Array)
          params["#{key}[]"] = value
        else
          params[key.to_s] = value
        end
      end
      params
    end
  end
end
