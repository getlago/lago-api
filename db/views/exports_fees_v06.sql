SELECT
    f.organization_id,
    f.id AS lago_id,
    f.charge_id AS lago_charge_id,
    f.fixed_charge_id AS lago_fixed_charge_id,
    f.charge_filter_id AS lago_charge_filter_id,
    f.invoice_id AS lago_invoice_id,
    f.subscription_id AS lago_subscription_id,
    -- Contract fees have no subscription: their customer comes from the contract.
    COALESCE(c.id, ct.customer_id) AS lago_customer_id,
    json_build_object(
        'type', CASE f.fee_type
            WHEN 0 THEN 'charge'       -- Assuming 0 maps to :charge
            WHEN 1 THEN 'add_on'       -- Assuming 1 maps to :add_on
            WHEN 2 THEN 'subscription' -- Assuming 2 maps to :subscription
            WHEN 3 THEN 'credit'       -- Assuming 3 maps to :credit
            WHEN 4 THEN 'commitment'   -- Assuming 4 maps to :commitment
            WHEN 5 THEN 'fixed_charge' -- Assuming 5 maps to :fixed_charge
            WHEN 6 THEN 'product'      -- Assuming 6 maps to :product
            WHEN 7 THEN 'credit_purchase' -- Assuming 7 maps to :credit_purchase
            ELSE 'unknown'
        END,
        'code', CASE f.fee_type
            WHEN 0 THEN bm.code -- 0 is charge
            WHEN 1 THEN ao.code -- 1 is add_on
            WHEN 3 THEN 'credit' -- 3 is credit
            WHEN 5 THEN fao.code -- 5 is fixed_charge
            WHEN 6 THEN pr.code -- 6 is product
            WHEN 7 THEN 'credit_purchase' -- 7 is credit_purchase
            ELSE p.code -- everything else is subscription
        END,
        'name', CASE f.fee_type
            WHEN 0 THEN bm.name -- 0 is charge
            WHEN 1 THEN ao.name -- 1 is add_on
            WHEN 3 THEN 'credit' -- 3 is credit
            WHEN 5 THEN fao.name -- 5 is fixed_charge
            WHEN 6 THEN pr.name -- 6 is product
            WHEN 7 THEN 'credit_purchase' -- 7 is credit_purchase
            ELSE p.name -- everything else is subscription
        END,
        'description', CASE f.fee_type
            WHEN 0 THEN bm.description -- 0 is charge
            WHEN 1 THEN ao.description -- 1 is add_on
            WHEN 3 THEN 'credit' -- 3 is credit
            WHEN 5 THEN fao.description -- 5 is fixed_charge
            WHEN 6 THEN pr.description -- 6 is product
            WHEN 7 THEN 'credit_purchase' -- 7 is credit_purchase
            ELSE p.description -- everything else is subscription
        END,
        'invoice_display_name', COALESCE(
            f.invoice_display_name,
            CASE f.fee_type
                WHEN 0 THEN COALESCE(
                    ch.invoice_display_name,
                    bm.name
                ) -- 0 is charge
                WHEN 1 THEN COALESCE(ao.invoice_display_name, ao.name) -- 1 is add_on
                WHEN 3 THEN 'credit' -- 3 is credit
                WHEN 5 THEN COALESCE(
                    fc.invoice_display_name,
                    fao.invoice_display_name,
                    fao.name
                ) -- 5 is fixed_charge
                -- 6 is product: a blank display name falls back to the name, like Product#invoice_name
                WHEN 6 THEN COALESCE(
                    CASE WHEN pr.invoice_display_name !~ '^[[:space:]]*$' THEN pr.invoice_display_name END,
                    pr.name
                )
                WHEN 7 THEN 'credit_purchase' -- 7 is credit_purchase
                ELSE p.invoice_display_name -- everything else is subscription
            END
        ),
        'filters', (
            SELECT json_agg(
                json_build_object(
                    'id', cf.id,
                    'charge_id', cf.charge_id,
                    'properties', cf.properties,
                    'invoice_display_name', cf.invoice_display_name
                )
            )
            FROM charge_filters AS cf
            WHERE cf.charge_id = f.charge_id
        ),
        'lago_item_id', CASE f.fee_type
            WHEN 0 THEN bm.id -- 0 is charge
            WHEN 1 THEN ao.id -- 1 is add_on
            WHEN 3 THEN f.invoiceable_id -- 3 is credit
            WHEN 5 THEN fao.id -- 5 is fixed_charge
            WHEN 6 THEN pr.id -- 6 is product
            WHEN 7 THEN f.invoiceable_id -- 7 is credit_purchase
            ELSE f.subscription_id -- everything else is subscription
        END,
        'item_type', CASE f.fee_type
            WHEN 0 THEN 'billable_metric' -- 0 is charge
            WHEN 1 THEN 'add_on' -- 1 is add_on
            WHEN 3 THEN 'wallet_transaction' -- 3 is credit
            WHEN 5 THEN 'add_on' -- 5 is fixed_charge, whose item is the add-on behind it
            WHEN 6 THEN 'product' -- 6 is product
            WHEN 7 THEN 'catalog_wallet_transaction' -- 7 is credit_purchase
            ELSE 'subscription' -- everything else is subscription
        END,
        'grouped_by', f.grouped_by
    ) AS item,
    f.pay_in_advance,
    f.amount_cents,
    CASE f.fee_type
        WHEN 6 THEN rc.display_on_invoice -- product fees are invoiceable when their rate card shows on invoices
        ELSE ch.invoiceable
    END AS invoiceable,
    f.taxes_amount_cents,
    f.taxes_precise_amount_cents,
    f.taxes_rate,
    f.amount_cents + f.taxes_amount_cents AS total_amount_cents,
    f.amount_currency AS currency,
    f.units,
    f.description,
    f.precise_amount_cents,
    f.precise_unit_amount,
    f.precise_coupons_amount_cents,
    f.precise_amount_cents + f.taxes_precise_amount_cents AS precise_total_amount_cents,
    f.precise_credit_notes_amount_cents,
    f.events_count,
    -- payment-status
    CASE f.payment_status
        WHEN 0 THEN 'pending'    -- Assuming 0 maps to :pending
        WHEN 1 THEN 'succeeded'  -- Assuming 1 maps to :succeeded
        WHEN 2 THEN 'failed'     -- Assuming 2 maps to :failed
        WHEN 3 THEN 'refunded'   -- Assuming 3 maps to :refunded
        ELSE 'unknown'
    END AS payment_status,
    f.created_at,
    f.succeeded_at,
    f.failed_at,
    f.refunded_at,
    f.amount_details,
    f.updated_at,
    CASE f.fee_type
        WHEN 0 THEN (f.properties->>'charges_from_datetime')::timestamptz::text
        WHEN 5 THEN (f.properties->>'fixed_charges_from_datetime')::timestamptz::text
        ELSE (f.properties->>'from_datetime')::timestamptz::text
    END AS from_date,
    CASE f.fee_type
        WHEN 0 THEN (f.properties->>'charges_to_datetime')::timestamptz::text
        WHEN 5 THEN (f.properties->>'fixed_charges_to_datetime')::timestamptz::text
        ELSE (f.properties->>'to_datetime')::timestamptz::text
    END AS to_date,
    f.contract_id AS lago_contract_id,
    f.contract_rate_card_id AS lago_contract_rate_card_id,
    f.rate_card_rate_id AS lago_rate_card_rate_id,
    f.product_filter_id AS lago_product_filter_id,
    rc.product_id AS lago_product_id,
    f.rate_override_id AS lago_rate_override_id
FROM fees AS f
LEFT JOIN subscriptions AS s ON f.subscription_id = s.id
LEFT JOIN customers AS c ON s.customer_id = c.id
LEFT JOIN charges AS ch ON f.charge_id = ch.id
LEFT JOIN billable_metrics AS bm ON ch.billable_metric_id = bm.id
LEFT JOIN add_ons AS ao ON f.add_on_id = ao.id
-- Fixed-charge fees carry fixed_charge_id, not charge_id. Their item is the
-- add-on the fixed charge is built from, so both hops are needed.
LEFT JOIN fixed_charges AS fc ON f.fixed_charge_id = fc.id
LEFT JOIN add_ons AS fao ON fc.add_on_id = fao.id
LEFT JOIN plans AS p ON s.plan_id = p.id
-- Product fees (contracts) reach their product through the rate card of their rate.
-- Plain joins, without a deleted_at filter: a fee keeps pointing at the catalog rows
-- it was billed from even after they are deleted.
LEFT JOIN contracts AS ct ON f.contract_id = ct.id
LEFT JOIN rate_card_rates AS rcr ON f.rate_card_rate_id = rcr.id
LEFT JOIN rate_cards AS rc ON rcr.rate_card_id = rc.id
LEFT JOIN products AS pr ON rc.product_id = pr.id
-- LEFT JOIN so fees with no invoice (e.g. recurring non-invoiceable fees) are kept.
-- IS DISTINCT FROM keeps those NULL-invoice rows while excluding deleted invoices.
LEFT JOIN invoices AS i ON i.id = f.invoice_id
WHERE i.status IS DISTINCT FROM 8; -- exclude deleted invoices
