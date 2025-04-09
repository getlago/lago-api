SELECT
  c.id AS lago_id,
  be.code AS billing_entity_code,
  c.external_id,
  c.account_type::text,
  c.name,
  c.firstname,
  c.lastname,
  c.customer_type::text,
  c.sequential_id,
  c.slug,
  c.created_at,
  c.updated_at,
  c.country,
  c.address_line1,
  c.address_line2,
  c.state,
  c.zipcode,
  c.email,
  c.city,
  c.url,
  c.phone,
  c.logo_url,
  c.legal_name,
  c.legal_number,
  c.currency,
  c.tax_identification_number,
  c.timezone,
  COALESCE(c.timezone, o.timezone, 'UTC') AS applicable_timezone,
  c.net_payment_term,
  c.external_salesforce_id,
  c.finalize_zero_amount_invoice,
  c.skip_invoice_custom_sections,
  c.payment_provider,
  c.payment_provider_code,
  c.invoice_grace_period,
  COALESCE(c.invoice_grace_period, o.invoice_grace_period) AS applicable_invoice_grace_period,
  c.document_locale,
  ppc.provider_customer_id,
  CASE
    WHEN c.payment_provider = 'stripe' THEN ppc.settings->>'provider_payment_methods'
    ELSE NULL
  END AS provider_payment_methods,
  ppc.settings AS provider_settings,
  c.shipping_address_line1,
  c.shipping_address_line2, 
  c.shipping_city,
  c.shipping_zipcode,
  c.shipping_state,
  c.shipping_country,
  COALESCE(
    (
      SELECT json_agg(
        json_build_object(
          'id', cm.id, 
          'key', cm.key, 
          'value', cm.value, 
          'display_in_invoice', cm.display_in_invoice
        )
      )
      FROM customer_metadata cm
      WHERE cm.customer_id = c.id
    ),
    '{}'::json
  ) AS metadata,
  COALESCE(
    (
      SELECT json_agg(
        json_build_object(
          'tax_id', t.id,
          'code', t.code,
          'name', t.name,
          'rate', t.rate,
          'description', t.description
        )
      )
      FROM customers_taxes ct
      JOIN taxes t ON t.id = ct.tax_id
      WHERE ct.customer_id = c.id
    ),
    '{}'::json
  ) AS taxes
FROM customers c
LEFT JOIN organizations o ON o.id = c.organization_id
LEFT JOIN billing_entities be ON be.id = c.billing_entity_id
  AND be.deleted_at IS NULL
LEFT JOIN payment_provider_customers ppc ON ppc.customer_id = c.id 
  AND ppc.deleted_at IS NULL
WHERE c.deleted_at IS NULL 