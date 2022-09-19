# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2022_09_19_133338) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.uuid "record_id"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "add_ons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code", null: false
    t.string "description"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_add_ons_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_add_ons_on_organization_id"
  end

  create_table "applied_add_ons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "add_on_id", null: false
    t.uuid "customer_id", null: false
    t.integer "amount_cents", null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["add_on_id", "customer_id"], name: "index_applied_add_ons_on_add_on_id_and_customer_id"
    t.index ["add_on_id"], name: "index_applied_add_ons_on_add_on_id"
    t.index ["customer_id"], name: "index_applied_add_ons_on_customer_id"
  end

  create_table "applied_coupons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "coupon_id", null: false
    t.uuid "customer_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "amount_cents", null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "terminated_at", precision: nil
    t.index ["coupon_id", "customer_id"], name: "index_applied_coupons_on_coupon_id_and_customer_id", unique: true, where: "(status = 0)"
    t.index ["coupon_id"], name: "index_applied_coupons_on_coupon_id"
    t.index ["customer_id"], name: "index_applied_coupons_on_customer_id"
  end

  create_table "billable_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code", null: false
    t.string "description"
    t.jsonb "properties", default: {}
    t.integer "aggregation_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "field_name"
    t.index ["organization_id", "code"], name: "index_billable_metrics_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_billable_metrics_on_organization_id"
  end

  create_table "charges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "billable_metric_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "plan_id"
    t.string "amount_currency"
    t.integer "charge_model", default: 0, null: false
    t.jsonb "properties", default: "{}", null: false
    t.index ["billable_metric_id"], name: "index_charges_on_billable_metric_id"
    t.index ["plan_id"], name: "index_charges_on_plan_id"
  end

  create_table "coupons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code"
    t.integer "status", default: 0, null: false
    t.datetime "terminated_at"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.integer "expiration", null: false
    t.integer "expiration_duration"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_coupons_on_organization_id_and_code", unique: true, where: "(code IS NOT NULL)"
    t.index ["organization_id"], name: "index_coupons_on_organization_id"
  end

  create_table "credits", force: :cascade do |t|
    t.uuid "invoice_id"
    t.uuid "applied_coupon_id"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["applied_coupon_id"], name: "index_credits_on_applied_coupon_id"
    t.index ["invoice_id"], name: "index_credits_on_invoice_id"
  end

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "external_id", null: false
    t.string "name"
    t.uuid "organization_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "country"
    t.string "address_line1"
    t.string "address_line2"
    t.string "state"
    t.string "zipcode"
    t.string "email"
    t.string "city"
    t.string "url"
    t.string "phone"
    t.string "logo_url"
    t.string "legal_name"
    t.string "legal_number"
    t.float "vat_rate"
    t.string "payment_provider"
    t.string "slug"
    t.bigint "sequential_id"
    t.string "currency"
    t.index ["external_id"], name: "index_customers_on_external_id"
    t.index ["organization_id"], name: "index_customers_on_organization_id"
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "customer_id", null: false
    t.string "transaction_id", null: false
    t.string "code", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "timestamp", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "subscription_id"
    t.index ["customer_id"], name: "index_events_on_customer_id"
    t.index ["organization_id", "code"], name: "index_events_on_organization_id_and_code"
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.index ["subscription_id", "code"], name: "index_events_on_subscription_id_and_code"
    t.index ["subscription_id", "transaction_id"], name: "index_events_on_subscription_id_and_transaction_id", unique: true
    t.index ["subscription_id"], name: "index_events_on_subscription_id"
  end

  create_table "fees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id"
    t.uuid "charge_id"
    t.uuid "subscription_id"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.bigint "vat_amount_cents", null: false
    t.string "vat_amount_currency", null: false
    t.float "vat_rate"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "units", default: "0.0", null: false
    t.uuid "applied_add_on_id"
    t.jsonb "properties", default: {}, null: false
    t.integer "events_count"
    t.integer "fee_type"
    t.string "invoiceable_type"
    t.uuid "invoiceable_id"
    t.index ["applied_add_on_id"], name: "index_fees_on_applied_add_on_id"
    t.index ["charge_id"], name: "index_fees_on_charge_id"
    t.index ["invoice_id"], name: "index_fees_on_invoice_id"
    t.index ["invoiceable_type", "invoiceable_id"], name: "index_fees_on_invoiceable"
    t.index ["subscription_id"], name: "index_fees_on_subscription_id"
  end

  create_table "invites", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "membership_id"
    t.string "email", null: false
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id"], name: "index_invites_on_membership_id"
    t.index ["organization_id"], name: "index_invites_on_organization_id"
    t.index ["token"], name: "index_invites_on_token", unique: true
  end

  create_table "invoice_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "subscription_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_invoice_subscriptions_on_invoice_id"
    t.index ["subscription_id"], name: "index_invoice_subscriptions_on_subscription_id"
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "issuing_date"
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency"
    t.bigint "vat_amount_cents", default: 0, null: false
    t.string "vat_amount_currency"
    t.bigint "total_amount_cents", default: 0, null: false
    t.string "total_amount_currency"
    t.integer "invoice_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "number", default: "", null: false
    t.integer "sequential_id"
    t.string "file"
    t.uuid "customer_id"
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "revoked_at"
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key"
    t.string "webhook_url"
    t.float "vat_rate", default: 0.0, null: false
    t.string "country"
    t.string "address_line1"
    t.string "address_line2"
    t.string "state"
    t.string "zipcode"
    t.string "email"
    t.string "city"
    t.string "logo"
    t.string "legal_name"
    t.string "legal_number"
    t.text "invoice_footer"
    t.index ["api_key"], name: "index_organizations_on_api_key", unique: true
  end

  create_table "payment_provider_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "payment_provider_id"
    t.string "type", null: false
    t.string "provider_customer_id"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payment_provider_customers_on_customer_id"
    t.index ["payment_provider_id"], name: "index_payment_provider_customers_on_payment_provider_id"
    t.index ["provider_customer_id"], name: "index_payment_provider_customers_on_provider_customer_id"
  end

  create_table "payment_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "type", null: false
    t.string "secrets"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_payment_providers_on_organization_id"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "payment_provider_id"
    t.uuid "payment_provider_customer_id"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.string "provider_payment_id", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_payments_on_invoice_id"
    t.index ["payment_provider_customer_id"], name: "index_payments_on_payment_provider_customer_id"
    t.index ["payment_provider_id"], name: "index_payments_on_payment_provider_id"
  end

  create_table "persisted_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.string "external_subscription_id", null: false
    t.string "external_id", null: false
    t.datetime "added_at", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "billable_metric_id"
    t.index ["billable_metric_id"], name: "index_persisted_events_on_billable_metric_id"
    t.index ["customer_id", "external_subscription_id", "billable_metric_id"], name: "index_search_persisted_events"
    t.index ["customer_id"], name: "index_persisted_events_on_customer_id"
    t.index ["external_id"], name: "index_persisted_events_on_external_id"
  end

  create_table "plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "code", null: false
    t.integer "interval", null: false
    t.string "description"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.float "trial_period"
    t.boolean "pay_in_advance", default: false, null: false
    t.boolean "bill_charges_monthly"
    t.uuid "parent_id"
    t.index ["code", "organization_id"], name: "index_plans_on_code_and_organization_id", unique: true
    t.index ["organization_id"], name: "index_plans_on_organization_id"
    t.index ["parent_id"], name: "index_plans_on_parent_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "plan_id", null: false
    t.integer "status", null: false
    t.datetime "canceled_at", precision: nil
    t.datetime "terminated_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "previous_subscription_id"
    t.date "subscription_date"
    t.string "name"
    t.string "external_id", null: false
    t.integer "billing_time", default: 0, null: false
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["external_id"], name: "index_subscriptions_on_external_id"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "wallet_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "wallet_id", null: false
    t.integer "transaction_type", null: false
    t.integer "status", null: false
    t.decimal "amount", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "credit_amount", precision: 30, scale: 5, default: "0.0", null: false
    t.datetime "settled_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "invoice_id"
    t.index ["invoice_id"], name: "index_wallet_transactions_on_invoice_id"
    t.index ["wallet_id"], name: "index_wallet_transactions_on_wallet_id"
  end

  create_table "wallets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.integer "status", null: false
    t.string "currency", null: false
    t.string "name"
    t.decimal "rate_amount", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "credits_balance", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "balance", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "consumed_credits", precision: 30, scale: 5, default: "0.0", null: false
    t.datetime "expiration_date", precision: nil
    t.datetime "last_balance_sync_at", precision: nil
    t.datetime "last_consumed_credit_at", precision: nil
    t.datetime "terminated_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "consumed_amount", precision: 30, scale: 5, default: "0.0"
    t.index ["customer_id"], name: "index_wallets_on_customer_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "add_ons", "organizations"
  add_foreign_key "applied_add_ons", "add_ons"
  add_foreign_key "applied_add_ons", "customers"
  add_foreign_key "billable_metrics", "organizations"
  add_foreign_key "charges", "billable_metrics"
  add_foreign_key "charges", "plans"
  add_foreign_key "credits", "applied_coupons"
  add_foreign_key "credits", "invoices"
  add_foreign_key "customers", "organizations"
  add_foreign_key "events", "customers"
  add_foreign_key "events", "organizations"
  add_foreign_key "events", "subscriptions"
  add_foreign_key "fees", "applied_add_ons"
  add_foreign_key "fees", "charges"
  add_foreign_key "fees", "invoices"
  add_foreign_key "fees", "subscriptions"
  add_foreign_key "invites", "memberships"
  add_foreign_key "invites", "organizations"
  add_foreign_key "invoice_subscriptions", "invoices"
  add_foreign_key "invoice_subscriptions", "subscriptions"
  add_foreign_key "invoices", "customers"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "payment_provider_customers", "customers"
  add_foreign_key "payment_provider_customers", "payment_providers"
  add_foreign_key "payment_providers", "organizations"
  add_foreign_key "payments", "invoices"
  add_foreign_key "payments", "payment_providers"
  add_foreign_key "persisted_events", "customers"
  add_foreign_key "plans", "organizations"
  add_foreign_key "plans", "plans", column: "parent_id"
  add_foreign_key "subscriptions", "customers"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "wallet_transactions", "invoices"
  add_foreign_key "wallet_transactions", "wallets"
  add_foreign_key "wallets", "customers"
end
