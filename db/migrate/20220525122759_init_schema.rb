# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'pgcrypto'

    create_table 'add_ons', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.string 'name', null: false
      t.string 'code', null: false
      t.string 'description'
      t.bigint 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[organization_id code], name: 'index_add_ons_on_organization_id_and_code', unique: true
      t.index ['organization_id'], name: 'index_add_ons_on_organization_id'
    end

    create_table 'applied_coupons', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'coupon_id', null: false
      t.uuid 'customer_id', null: false
      t.integer 'status', default: 0, null: false
      t.integer 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.datetime 'terminated_at', precision: nil
      t.index %w[coupon_id customer_id],
        name: 'index_applied_coupons_on_coupon_id_and_customer_id',
        unique: true,
        where: '(status = 0)'
      t.index ['coupon_id'], name: 'index_applied_coupons_on_coupon_id'
      t.index ['customer_id'], name: 'index_applied_coupons_on_customer_id'
    end

    create_table 'billable_metrics', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.string 'name', null: false
      t.string 'code', null: false
      t.string 'description'
      t.jsonb 'properties', default: {}
      t.integer 'aggregation_type', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'field_name'
      t.index %w[organization_id code], name: 'index_billable_metrics_on_organization_id_and_code', unique: true
      t.index ['organization_id'], name: 'index_billable_metrics_on_organization_id'
    end

    create_table 'charges', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'billable_metric_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.uuid 'plan_id'
      t.string 'amount_currency', null: false
      t.integer 'charge_model', default: 0, null: false
      t.jsonb 'properties', default: '{}', null: false
      t.index ['billable_metric_id'], name: 'index_charges_on_billable_metric_id'
      t.index ['plan_id'], name: 'index_charges_on_plan_id'
    end

    create_table 'coupons', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.string 'name', null: false
      t.string 'code'
      t.integer 'status', default: 0, null: false
      t.datetime 'terminated_at'
      t.bigint 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.integer 'expiration', null: false
      t.integer 'expiration_duration'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[organization_id code],
        name: 'index_coupons_on_organization_id_and_code',
        unique: true,
        where: '(code IS NOT NULL)'
      t.index ['organization_id'], name: 'index_coupons_on_organization_id'
    end

    create_table 'credits', force: :cascade do |t|
      t.uuid 'invoice_id'
      t.uuid 'applied_coupon_id'
      t.bigint 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['applied_coupon_id'], name: 'index_credits_on_applied_coupon_id'
      t.index ['invoice_id'], name: 'index_credits_on_invoice_id'
    end

    create_table 'customers', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.string 'customer_id', null: false
      t.string 'name'
      t.uuid 'organization_id', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'country'
      t.string 'address_line1'
      t.string 'address_line2'
      t.string 'state'
      t.string 'zipcode'
      t.string 'email'
      t.string 'city'
      t.string 'url'
      t.string 'phone'
      t.string 'logo_url'
      t.string 'legal_name'
      t.string 'legal_number'
      t.float 'vat_rate'
      t.index ['customer_id'], name: 'index_customers_on_customer_id'
      t.index ['organization_id'], name: 'index_customers_on_organization_id'
    end

    create_table 'events', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.uuid 'customer_id', null: false
      t.string 'transaction_id', null: false
      t.string 'code', null: false
      t.jsonb 'properties', default: {}, null: false
      t.datetime 'timestamp', precision: nil
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['customer_id'], name: 'index_events_on_customer_id'
      t.index %w[organization_id code], name: 'index_events_on_organization_id_and_code'
      t.index %w[organization_id transaction_id],
        name: 'index_events_on_organization_id_and_transaction_id',
        unique: true
      t.index ['organization_id'], name: 'index_events_on_organization_id'
    end

    create_table 'fees', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'invoice_id'
      t.uuid 'charge_id'
      t.uuid 'subscription_id'
      t.bigint 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.bigint 'vat_amount_cents', null: false
      t.string 'vat_amount_currency', null: false
      t.float 'vat_rate'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.decimal 'units', default: '0.0', null: false
      t.index ['charge_id'], name: 'index_fees_on_charge_id'
      t.index ['invoice_id'], name: 'index_fees_on_invoice_id'
      t.index ['subscription_id'], name: 'index_fees_on_subscription_id'
    end

    create_table 'invoices', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'subscription_id', null: false
      t.date 'from_date', null: false
      t.date 'to_date', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.date 'issuing_date'
      t.bigint 'amount_cents', default: 0, null: false
      t.string 'amount_currency'
      t.bigint 'vat_amount_cents', default: 0, null: false
      t.string 'vat_amount_currency'
      t.bigint 'total_amount_cents', default: 0, null: false
      t.string 'total_amount_currency'
      t.integer 'sequential_id'
      t.index ['sequential_id'], name: 'index_invoices_on_sequential_id'
      t.index ['subscription_id'], name: 'index_invoices_on_subscription_id'
    end

    create_table 'memberships', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.uuid 'user_id', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.integer 'role', default: 0, null: false
      t.index ['organization_id'], name: 'index_memberships_on_organization_id'
      t.index ['user_id'], name: 'index_memberships_on_user_id'
    end

    create_table 'organizations', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.string 'name', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'api_key'
      t.string 'webhook_url'
      t.float 'vat_rate', default: 0.0, null: false
      t.index ['api_key'], name: 'index_organizations_on_api_key', unique: true
    end

    create_table 'plans', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'organization_id', null: false
      t.string 'name', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'code', null: false
      t.integer 'interval', null: false
      t.string 'description'
      t.bigint 'amount_cents', null: false
      t.string 'amount_currency', null: false
      t.float 'trial_period'
      t.boolean 'pay_in_advance', default: false, null: false
      t.index %w[code organization_id], name: 'index_plans_on_code_and_organization_id', unique: true
      t.index ['organization_id'], name: 'index_plans_on_organization_id'
    end

    create_table 'subscriptions', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.uuid 'customer_id', null: false
      t.uuid 'plan_id', null: false
      t.integer 'status', null: false
      t.datetime 'canceled_at', precision: nil
      t.datetime 'terminated_at', precision: nil
      t.datetime 'started_at', precision: nil
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.uuid 'previous_subscription_id'
      t.date 'anniversary_date'
      t.index ['customer_id'], name: 'index_subscriptions_on_customer_id'
      t.index ['plan_id'], name: 'index_subscriptions_on_plan_id'
    end

    create_table 'users', id: :uuid, default: -> { 'gen_random_uuid()' }, force: :cascade do |t|
      t.string 'email'
      t.string 'password_digest'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
    end

    add_foreign_key 'add_ons', 'organizations'
    add_foreign_key 'billable_metrics', 'organizations'
    add_foreign_key 'charges', 'billable_metrics'
    add_foreign_key 'charges', 'plans'
    add_foreign_key 'credits', 'applied_coupons'
    add_foreign_key 'credits', 'invoices'
    add_foreign_key 'customers', 'organizations'
    add_foreign_key 'events', 'customers'
    add_foreign_key 'events', 'organizations'
    add_foreign_key 'fees', 'charges'
    add_foreign_key 'fees', 'invoices'
    add_foreign_key 'fees', 'subscriptions'
    add_foreign_key 'invoices', 'subscriptions'
    add_foreign_key 'memberships', 'organizations'
    add_foreign_key 'memberships', 'users'
    add_foreign_key 'plans', 'organizations'
    add_foreign_key 'subscriptions', 'customers'
    add_foreign_key 'subscriptions', 'plans'
  end
end
