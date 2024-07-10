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

ActiveRecord::Schema[7.1].define(version: 2024_07_08_195226) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "billable_metric_weighted_interval", ["seconds"]
  create_enum "subscription_invoicing_reason", ["subscription_starting", "subscription_periodic", "subscription_terminating", "in_advance_charge", "in_advance_charge_periodic"]

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
    t.datetime "deleted_at"
    t.string "invoice_display_name"
    t.index ["deleted_at"], name: "index_add_ons_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_add_ons_on_organization_id_and_code", unique: true, where: "(deleted_at IS NULL)"
    t.index ["organization_id"], name: "index_add_ons_on_organization_id"
  end

  create_table "add_ons_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "add_on_id", null: false
    t.uuid "tax_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["add_on_id", "tax_id"], name: "index_add_ons_taxes_on_add_on_id_and_tax_id", unique: true
    t.index ["add_on_id"], name: "index_add_ons_taxes_on_add_on_id"
    t.index ["tax_id"], name: "index_add_ons_taxes_on_tax_id"
  end

  create_table "adjusted_fees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "fee_id"
    t.uuid "invoice_id", null: false
    t.uuid "subscription_id"
    t.uuid "charge_id"
    t.string "invoice_display_name"
    t.integer "fee_type"
    t.boolean "adjusted_units", default: false, null: false
    t.boolean "adjusted_amount", default: false, null: false
    t.decimal "units", default: "0.0", null: false
    t.bigint "unit_amount_cents", default: 0, null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "group_id"
    t.jsonb "grouped_by", default: {}, null: false
    t.uuid "charge_filter_id"
    t.index ["charge_filter_id"], name: "index_adjusted_fees_on_charge_filter_id"
    t.index ["charge_id"], name: "index_adjusted_fees_on_charge_id"
    t.index ["fee_id"], name: "index_adjusted_fees_on_fee_id"
    t.index ["group_id"], name: "index_adjusted_fees_on_group_id"
    t.index ["invoice_id"], name: "index_adjusted_fees_on_invoice_id"
    t.index ["subscription_id"], name: "index_adjusted_fees_on_subscription_id"
  end

  create_table "applied_add_ons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "add_on_id", null: false
    t.uuid "customer_id", null: false
    t.bigint "amount_cents", null: false
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
    t.bigint "amount_cents"
    t.string "amount_currency"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "terminated_at", precision: nil
    t.decimal "percentage_rate", precision: 10, scale: 5
    t.integer "frequency", default: 0, null: false
    t.integer "frequency_duration"
    t.integer "frequency_duration_remaining"
    t.index ["coupon_id"], name: "index_applied_coupons_on_coupon_id"
    t.index ["customer_id"], name: "index_applied_coupons_on_customer_id"
  end

  create_table "billable_metric_filters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "billable_metric_id", null: false
    t.string "key", null: false
    t.string "values", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["billable_metric_id"], name: "index_active_metric_filters", where: "(deleted_at IS NULL)"
    t.index ["billable_metric_id"], name: "index_billable_metric_filters_on_billable_metric_id"
    t.index ["deleted_at"], name: "index_billable_metric_filters_on_deleted_at"
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
    t.datetime "deleted_at"
    t.boolean "recurring", default: false, null: false
    t.enum "weighted_interval", enum_type: "billable_metric_weighted_interval"
    t.text "custom_aggregator"
    t.index ["deleted_at"], name: "index_billable_metrics_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_billable_metrics_on_organization_id_and_code", unique: true, where: "(deleted_at IS NULL)"
    t.index ["organization_id"], name: "index_billable_metrics_on_organization_id"
  end

  create_table "cached_aggregations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "event_id"
    t.datetime "timestamp", null: false
    t.string "external_subscription_id", null: false
    t.uuid "charge_id", null: false
    t.uuid "group_id"
    t.decimal "current_aggregation"
    t.decimal "max_aggregation"
    t.decimal "max_aggregation_with_proration"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "grouped_by", default: {}, null: false
    t.uuid "charge_filter_id"
    t.decimal "current_amount"
    t.string "event_transaction_id"
    t.index ["charge_id"], name: "index_cached_aggregations_on_charge_id"
    t.index ["event_id"], name: "index_cached_aggregations_on_event_id"
    t.index ["external_subscription_id"], name: "index_cached_aggregations_on_external_subscription_id"
    t.index ["group_id"], name: "index_cached_aggregations_on_group_id"
    t.index ["organization_id", "event_transaction_id"], name: "index_cached_aggregations_on_event_transaction_id"
    t.index ["organization_id", "timestamp", "charge_id", "charge_filter_id"], name: "index_timestamp_filter_lookup"
    t.index ["organization_id", "timestamp", "charge_id", "group_id"], name: "index_timestamp_group_lookup"
    t.index ["organization_id", "timestamp", "charge_id"], name: "index_timestamp_lookup"
    t.index ["organization_id"], name: "index_cached_aggregations_on_organization_id"
  end

  create_table "charge_filter_values", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "charge_filter_id", null: false
    t.uuid "billable_metric_filter_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "values", default: [], null: false, array: true
    t.index ["billable_metric_filter_id"], name: "index_charge_filter_values_on_billable_metric_filter_id"
    t.index ["charge_filter_id"], name: "index_active_charge_filter_values", where: "(deleted_at IS NULL)"
    t.index ["charge_filter_id"], name: "index_charge_filter_values_on_charge_filter_id"
    t.index ["deleted_at"], name: "index_charge_filter_values_on_deleted_at"
  end

  create_table "charge_filters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "charge_id", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "invoice_display_name"
    t.index ["charge_id"], name: "index_active_charge_filters", where: "(deleted_at IS NULL)"
    t.index ["charge_id"], name: "index_charge_filters_on_charge_id"
    t.index ["deleted_at"], name: "index_charge_filters_on_deleted_at"
  end

  create_table "charges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "billable_metric_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "plan_id"
    t.string "amount_currency"
    t.integer "charge_model", default: 0, null: false
    t.jsonb "properties", default: "{}", null: false
    t.datetime "deleted_at"
    t.boolean "pay_in_advance", default: false, null: false
    t.bigint "min_amount_cents", default: 0, null: false
    t.boolean "invoiceable", default: true, null: false
    t.boolean "prorated", default: false, null: false
    t.string "invoice_display_name"
    t.integer "regroup_paid_fees"
    t.index ["billable_metric_id"], name: "index_charges_on_billable_metric_id"
    t.index ["deleted_at"], name: "index_charges_on_deleted_at"
    t.index ["plan_id"], name: "index_charges_on_plan_id"
  end

  create_table "charges_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "charge_id", null: false
    t.uuid "tax_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["charge_id", "tax_id"], name: "index_charges_taxes_on_charge_id_and_tax_id", unique: true
    t.index ["charge_id"], name: "index_charges_taxes_on_charge_id"
    t.index ["tax_id"], name: "index_charges_taxes_on_tax_id"
  end

  create_table "commitments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plan_id", null: false
    t.integer "commitment_type", null: false
    t.bigint "amount_cents", null: false
    t.string "invoice_display_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commitment_type", "plan_id"], name: "index_commitments_on_commitment_type_and_plan_id", unique: true
    t.index ["plan_id"], name: "index_commitments_on_plan_id"
  end

  create_table "commitments_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "commitment_id", null: false
    t.uuid "tax_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["commitment_id"], name: "index_commitments_taxes_on_commitment_id"
    t.index ["tax_id"], name: "index_commitments_taxes_on_tax_id"
  end

  create_table "coupon_targets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "coupon_id", null: false
    t.uuid "plan_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.uuid "billable_metric_id"
    t.index ["billable_metric_id"], name: "index_coupon_targets_on_billable_metric_id"
    t.index ["coupon_id"], name: "index_coupon_targets_on_coupon_id"
    t.index ["deleted_at"], name: "index_coupon_targets_on_deleted_at"
    t.index ["plan_id"], name: "index_coupon_targets_on_plan_id"
  end

  create_table "coupons", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code"
    t.integer "status", default: 0, null: false
    t.datetime "terminated_at"
    t.bigint "amount_cents"
    t.string "amount_currency"
    t.integer "expiration", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "coupon_type", default: 0, null: false
    t.decimal "percentage_rate", precision: 10, scale: 5
    t.integer "frequency", default: 0, null: false
    t.integer "frequency_duration"
    t.datetime "expiration_at"
    t.boolean "reusable", default: true, null: false
    t.boolean "limited_plans", default: false, null: false
    t.datetime "deleted_at"
    t.boolean "limited_billable_metrics", default: false, null: false
    t.text "description"
    t.index ["deleted_at"], name: "index_coupons_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_coupons_on_organization_id_and_code", unique: true, where: "(deleted_at IS NULL)"
    t.index ["organization_id"], name: "index_coupons_on_organization_id"
  end

  create_table "credit_note_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "credit_note_id", null: false
    t.uuid "fee_id"
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "precise_amount_cents", precision: 30, scale: 5, null: false
    t.index ["credit_note_id"], name: "index_credit_note_items_on_credit_note_id"
    t.index ["fee_id"], name: "index_credit_note_items_on_fee_id"
  end

  create_table "credit_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "invoice_id", null: false
    t.integer "sequential_id", null: false
    t.string "number", null: false
    t.bigint "credit_amount_cents", default: 0, null: false
    t.string "credit_amount_currency", null: false
    t.integer "credit_status"
    t.bigint "balance_amount_cents", default: 0, null: false
    t.string "balance_amount_currency", default: "0", null: false
    t.integer "reason", null: false
    t.string "file"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "total_amount_cents", default: 0, null: false
    t.string "total_amount_currency", null: false
    t.bigint "refund_amount_cents", default: 0, null: false
    t.string "refund_amount_currency"
    t.integer "refund_status"
    t.datetime "voided_at"
    t.text "description"
    t.bigint "taxes_amount_cents", default: 0, null: false
    t.datetime "refunded_at"
    t.date "issuing_date", null: false
    t.integer "status", default: 1, null: false
    t.bigint "coupons_adjustment_amount_cents", default: 0, null: false
    t.decimal "precise_coupons_adjustment_amount_cents", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "precise_taxes_amount_cents", precision: 30, scale: 5, default: "0.0", null: false
    t.float "taxes_rate", default: 0.0, null: false
    t.index ["customer_id"], name: "index_credit_notes_on_customer_id"
    t.index ["invoice_id"], name: "index_credit_notes_on_invoice_id"
  end

  create_table "credit_notes_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "credit_note_id", null: false
    t.uuid "tax_id", null: false
    t.string "tax_description"
    t.string "tax_code", null: false
    t.string "tax_name", null: false
    t.float "tax_rate", default: 0.0, null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "base_amount_cents", default: 0, null: false
    t.index ["credit_note_id", "tax_id"], name: "index_credit_notes_taxes_on_credit_note_id_and_tax_id", unique: true
    t.index ["credit_note_id"], name: "index_credit_notes_taxes_on_credit_note_id"
    t.index ["tax_id"], name: "index_credit_notes_taxes_on_tax_id"
  end

  create_table "credits", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id"
    t.uuid "applied_coupon_id"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "credit_note_id"
    t.boolean "before_taxes", default: false, null: false
    t.index ["applied_coupon_id"], name: "index_credits_on_applied_coupon_id"
    t.index ["credit_note_id"], name: "index_credits_on_credit_note_id"
    t.index ["invoice_id"], name: "index_credits_on_invoice_id"
  end

  create_table "customer_metadata", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.string "key", null: false
    t.string "value", null: false
    t.boolean "display_in_invoice", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "key"], name: "index_customer_metadata_on_customer_id_and_key", unique: true
    t.index ["customer_id"], name: "index_customer_metadata_on_customer_id"
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
    t.integer "invoice_grace_period"
    t.string "timezone"
    t.datetime "deleted_at"
    t.string "document_locale"
    t.string "tax_identification_number"
    t.integer "net_payment_term"
    t.string "external_salesforce_id"
    t.string "payment_provider_code"
    t.string "shipping_address_line1"
    t.string "shipping_address_line2"
    t.string "shipping_city"
    t.string "shipping_zipcode"
    t.string "shipping_state"
    t.string "shipping_country"
    t.index ["deleted_at"], name: "index_customers_on_deleted_at"
    t.index ["external_id", "organization_id"], name: "index_customers_on_external_id_and_organization_id", unique: true, where: "(deleted_at IS NULL)"
    t.index ["organization_id"], name: "index_customers_on_organization_id"
    t.check_constraint "invoice_grace_period >= 0", name: "check_customers_on_invoice_grace_period"
    t.check_constraint "net_payment_term >= 0", name: "check_customers_on_net_payment_term"
  end

  create_table "customers_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "tax_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "tax_id"], name: "index_customers_taxes_on_customer_id_and_tax_id", unique: true
    t.index ["customer_id"], name: "index_customers_taxes_on_customer_id"
    t.index ["tax_id"], name: "index_customers_taxes_on_tax_id"
  end

  create_table "data_exports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "format"
    t.string "resource_type", null: false
    t.jsonb "resource_query", default: {}
    t.integer "status", default: 0, null: false
    t.datetime "expires_at", precision: nil
    t.datetime "started_at", precision: nil
    t.datetime "completed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "membership_id"
    t.uuid "organization_id"
    t.index ["membership_id"], name: "index_data_exports_on_membership_id"
    t.index ["organization_id"], name: "index_data_exports_on_organization_id"
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "customer_id"
    t.string "transaction_id", null: false
    t.string "code", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "timestamp", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "subscription_id"
    t.datetime "deleted_at"
    t.string "external_customer_id"
    t.string "external_subscription_id"
    t.index ["customer_id"], name: "index_events_on_customer_id"
    t.index ["deleted_at"], name: "index_events_on_deleted_at"
    t.index ["organization_id", "code", "created_at"], name: "index_events_on_organization_id_and_code_and_created_at", where: "(deleted_at IS NULL)"
    t.index ["organization_id", "code"], name: "index_events_on_organization_id_and_code"
    t.index ["organization_id", "external_subscription_id", "code", "timestamp"], name: "index_events_on_external_subscription_id_and_code_and_timestamp", where: "(deleted_at IS NULL)"
    t.index ["organization_id", "external_subscription_id", "transaction_id"], name: "index_unique_transaction_id", unique: true
    t.index ["organization_id", "timestamp"], name: "index_events_on_organization_id_and_timestamp", where: "(deleted_at IS NULL)"
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.index ["properties"], name: "index_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["subscription_id", "code", "timestamp"], name: "index_events_on_subscription_id_and_code_and_timestamp", where: "(deleted_at IS NULL)"
    t.index ["subscription_id"], name: "index_events_on_subscription_id"
  end

  create_table "fees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id"
    t.uuid "charge_id"
    t.uuid "subscription_id"
    t.bigint "amount_cents", null: false
    t.string "amount_currency", null: false
    t.bigint "taxes_amount_cents", null: false
    t.float "taxes_rate", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "units", default: "0.0", null: false
    t.uuid "applied_add_on_id"
    t.jsonb "properties", default: {}, null: false
    t.integer "fee_type"
    t.string "invoiceable_type"
    t.uuid "invoiceable_id"
    t.integer "events_count"
    t.uuid "group_id"
    t.uuid "pay_in_advance_event_id"
    t.integer "payment_status", default: 0, null: false
    t.datetime "succeeded_at"
    t.datetime "failed_at"
    t.datetime "refunded_at"
    t.uuid "true_up_parent_fee_id"
    t.uuid "add_on_id"
    t.string "description"
    t.bigint "unit_amount_cents", default: 0, null: false
    t.boolean "pay_in_advance", default: false, null: false
    t.decimal "precise_coupons_amount_cents", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "total_aggregated_units"
    t.string "invoice_display_name"
    t.decimal "precise_unit_amount", precision: 30, scale: 15, default: "0.0", null: false
    t.jsonb "amount_details", default: {}, null: false
    t.uuid "charge_filter_id"
    t.jsonb "grouped_by", default: {}, null: false
    t.string "pay_in_advance_event_transaction_id"
    t.datetime "deleted_at"
    t.index ["add_on_id"], name: "index_fees_on_add_on_id"
    t.index ["applied_add_on_id"], name: "index_fees_on_applied_add_on_id"
    t.index ["charge_filter_id"], name: "index_fees_on_charge_filter_id"
    t.index ["charge_id"], name: "index_fees_on_charge_id"
    t.index ["deleted_at"], name: "index_fees_on_deleted_at"
    t.index ["group_id"], name: "index_fees_on_group_id"
    t.index ["invoice_id"], name: "index_fees_on_invoice_id"
    t.index ["invoiceable_type", "invoiceable_id"], name: "index_fees_on_invoiceable"
    t.index ["subscription_id"], name: "index_fees_on_subscription_id"
    t.index ["true_up_parent_fee_id"], name: "index_fees_on_true_up_parent_fee_id"
  end

  create_table "fees_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "fee_id", null: false
    t.uuid "tax_id"
    t.string "tax_description"
    t.string "tax_code", null: false
    t.string "tax_name", null: false
    t.float "tax_rate", default: 0.0, null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fee_id", "tax_id"], name: "index_fees_taxes_on_fee_id_and_tax_id", unique: true, where: "(created_at >= '2023-09-12 00:00:00'::timestamp without time zone)"
    t.index ["fee_id"], name: "index_fees_taxes_on_fee_id"
    t.index ["tax_id"], name: "index_fees_taxes_on_tax_id"
  end

  create_table "group_properties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "charge_id", null: false
    t.uuid "group_id", null: false
    t.jsonb "values", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "invoice_display_name"
    t.index ["charge_id", "group_id"], name: "index_group_properties_on_charge_id_and_group_id", unique: true
    t.index ["charge_id"], name: "index_group_properties_on_charge_id"
    t.index ["deleted_at"], name: "index_group_properties_on_deleted_at"
    t.index ["group_id"], name: "index_group_properties_on_group_id"
  end

  create_table "groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "billable_metric_id", null: false
    t.uuid "parent_group_id"
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["billable_metric_id", "parent_group_id"], name: "index_groups_on_billable_metric_id_and_parent_group_id"
    t.index ["billable_metric_id"], name: "index_groups_on_billable_metric_id"
    t.index ["deleted_at"], name: "index_groups_on_deleted_at"
    t.index ["parent_group_id"], name: "index_groups_on_parent_group_id"
  end

  create_table "integration_collection_mappings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.integer "mapping_type", null: false
    t.string "type", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id"], name: "index_integration_collection_mappings_on_integration_id"
    t.index ["mapping_type", "integration_id"], name: "index_int_collection_mappings_on_mapping_type_and_int_id", unique: true
  end

  create_table "integration_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.uuid "customer_id", null: false
    t.string "external_customer_id"
    t.string "type", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "type"], name: "index_integration_customers_on_customer_id_and_type", unique: true
    t.index ["customer_id"], name: "index_integration_customers_on_customer_id"
    t.index ["external_customer_id"], name: "index_integration_customers_on_external_customer_id"
    t.index ["integration_id"], name: "index_integration_customers_on_integration_id"
  end

  create_table "integration_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.integer "item_type", null: false
    t.string "external_id", null: false
    t.string "external_account_code"
    t.string "external_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id", "integration_id", "item_type"], name: "index_int_items_on_external_id_and_int_id_and_type", unique: true
    t.index ["integration_id"], name: "index_integration_items_on_integration_id"
  end

  create_table "integration_mappings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "integration_id", null: false
    t.string "mappable_type", null: false
    t.uuid "mappable_id", null: false
    t.string "type", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["integration_id"], name: "index_integration_mappings_on_integration_id"
    t.index ["mappable_type", "mappable_id"], name: "index_integration_mappings_on_mappable"
  end

  create_table "integration_resources", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "syncable_type", null: false
    t.uuid "syncable_id", null: false
    t.string "external_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "integration_id"
    t.integer "resource_type", default: 0, null: false
    t.index ["integration_id"], name: "index_integration_resources_on_integration_id"
    t.index ["syncable_type", "syncable_id"], name: "index_integration_resources_on_syncable"
  end

  create_table "integrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code", null: false
    t.string "type", null: false
    t.string "secrets"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code", "organization_id"], name: "index_integrations_on_code_and_organization_id", unique: true
    t.index ["organization_id"], name: "index_integrations_on_organization_id"
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
    t.integer "role", default: 0, null: false
    t.index ["membership_id"], name: "index_invites_on_membership_id"
    t.index ["organization_id"], name: "index_invites_on_organization_id"
    t.index ["token"], name: "index_invites_on_token", unique: true
  end

  create_table "invoice_metadata", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "key"], name: "index_invoice_metadata_on_invoice_id_and_key", unique: true
    t.index ["invoice_id"], name: "index_invoice_metadata_on_invoice_id"
  end

  create_table "invoice_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "subscription_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "recurring"
    t.datetime "timestamp"
    t.datetime "from_datetime"
    t.datetime "to_datetime"
    t.datetime "charges_from_datetime"
    t.datetime "charges_to_datetime"
    t.enum "invoicing_reason", enum_type: "subscription_invoicing_reason"
    t.index ["invoice_id", "subscription_id"], name: "index_invoice_subscriptions_on_invoice_id_and_subscription_id", unique: true, where: "(created_at >= '2023-11-23 00:00:00'::timestamp without time zone)"
    t.index ["invoice_id"], name: "index_invoice_subscriptions_on_invoice_id"
    t.index ["subscription_id", "charges_from_datetime", "charges_to_datetime"], name: "index_invoice_subscriptions_on_charges_from_and_to_datetime", unique: true, where: "((created_at >= '2023-06-09 00:00:00'::timestamp without time zone) AND (recurring IS TRUE))"
    t.index ["subscription_id", "from_datetime", "to_datetime"], name: "index_invoice_subscriptions_boundaries"
    t.index ["subscription_id", "invoicing_reason"], name: "index_unique_starting_subscription_invoice", unique: true, where: "(invoicing_reason = 'subscription_starting'::subscription_invoicing_reason)"
    t.index ["subscription_id", "invoicing_reason"], name: "index_unique_terminating_subscription_invoice", unique: true, where: "(invoicing_reason = 'subscription_terminating'::subscription_invoicing_reason)"
    t.index ["subscription_id"], name: "index_invoice_subscriptions_on_subscription_id"
  end

  create_table "invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "issuing_date"
    t.bigint "taxes_amount_cents", default: 0, null: false
    t.bigint "total_amount_cents", default: 0, null: false
    t.integer "invoice_type", default: 0, null: false
    t.integer "payment_status", default: 0, null: false
    t.string "number", default: "", null: false
    t.integer "sequential_id"
    t.string "file"
    t.uuid "customer_id"
    t.float "taxes_rate", default: 0.0, null: false
    t.integer "status", default: 1, null: false
    t.string "timezone", default: "UTC", null: false
    t.integer "payment_attempts", default: 0, null: false
    t.boolean "ready_for_payment_processing", default: true, null: false
    t.uuid "organization_id", null: false
    t.integer "version_number", default: 4, null: false
    t.string "currency"
    t.bigint "fees_amount_cents", default: 0, null: false
    t.bigint "coupons_amount_cents", default: 0, null: false
    t.bigint "credit_notes_amount_cents", default: 0, null: false
    t.bigint "prepaid_credit_amount_cents", default: 0, null: false
    t.bigint "sub_total_excluding_taxes_amount_cents", default: 0, null: false
    t.bigint "sub_total_including_taxes_amount_cents", default: 0, null: false
    t.date "payment_due_date"
    t.integer "net_payment_term", default: 0, null: false
    t.datetime "voided_at"
    t.integer "organization_sequential_id", default: 0, null: false
    t.boolean "ready_to_be_refreshed", default: false, null: false
    t.datetime "payment_dispute_lost_at"
    t.boolean "skip_charges", default: false, null: false
    t.boolean "payment_overdue", default: false
    t.index ["customer_id", "sequential_id"], name: "index_invoices_on_customer_id_and_sequential_id", unique: true
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["organization_id"], name: "index_invoices_on_organization_id"
    t.index ["payment_overdue"], name: "index_invoices_on_payment_overdue"
    t.check_constraint "net_payment_term >= 0", name: "check_organizations_on_net_payment_term"
  end

  create_table "invoices_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.uuid "tax_id"
    t.string "tax_description"
    t.string "tax_code", null: false
    t.string "tax_name", null: false
    t.float "tax_rate", default: 0.0, null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "fees_amount_cents", default: 0, null: false
    t.index ["invoice_id", "tax_id"], name: "index_invoices_taxes_on_invoice_id_and_tax_id", unique: true, where: "(created_at >= '2023-09-12 00:00:00'::timestamp without time zone)"
    t.index ["invoice_id"], name: "index_invoices_taxes_on_invoice_id"
    t.index ["tax_id"], name: "index_invoices_taxes_on_tax_id"
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
    t.index ["user_id", "organization_id"], name: "index_memberships_on_user_id_and_organization_id", unique: true, where: "(revoked_at IS NULL)"
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
    t.integer "invoice_grace_period", default: 0, null: false
    t.string "timezone", default: "UTC", null: false
    t.string "document_locale", default: "en", null: false
    t.string "email_settings", default: [], null: false, array: true
    t.string "tax_identification_number"
    t.integer "net_payment_term", default: 0, null: false
    t.string "default_currency", default: "USD", null: false
    t.integer "document_numbering", default: 0, null: false
    t.string "document_number_prefix"
    t.boolean "eu_tax_management", default: false
    t.boolean "clickhouse_aggregation", default: false, null: false
    t.string "premium_integrations", default: [], null: false, array: true
    t.boolean "custom_aggregation", default: false
    t.index ["api_key"], name: "index_organizations_on_api_key", unique: true
    t.check_constraint "invoice_grace_period >= 0", name: "check_organizations_on_invoice_grace_period"
    t.check_constraint "net_payment_term >= 0", name: "check_organizations_on_net_payment_term"
  end

  create_table "password_resets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token", null: false
    t.datetime "expire_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_password_resets_on_token", unique: true
    t.index ["user_id"], name: "index_password_resets_on_user_id"
  end

  create_table "payment_provider_customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "payment_provider_id"
    t.string "type", null: false
    t.string "provider_customer_id"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "type"], name: "index_payment_provider_customers_on_customer_id_and_type", unique: true
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
    t.string "code", null: false
    t.string "name", null: false
    t.index ["code", "organization_id"], name: "index_payment_providers_on_code_and_organization_id", unique: true
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
    t.datetime "deleted_at"
    t.boolean "pending_deletion", default: false, null: false
    t.string "invoice_display_name"
    t.index ["created_at"], name: "index_plans_on_created_at"
    t.index ["deleted_at"], name: "index_plans_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_plans_on_organization_id_and_code", unique: true, where: "((deleted_at IS NULL) AND (parent_id IS NULL))"
    t.index ["organization_id"], name: "index_plans_on_organization_id"
    t.index ["parent_id"], name: "index_plans_on_parent_id"
  end

  create_table "plans_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "plan_id", null: false
    t.uuid "tax_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id", "tax_id"], name: "index_plans_taxes_on_plan_id_and_tax_id", unique: true
    t.index ["plan_id"], name: "index_plans_taxes_on_plan_id"
    t.index ["tax_id"], name: "index_plans_taxes_on_tax_id"
  end

  create_table "quantified_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "external_subscription_id", null: false
    t.string "external_id"
    t.datetime "added_at", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "billable_metric_id"
    t.jsonb "properties", default: {}, null: false
    t.datetime "deleted_at"
    t.uuid "group_id"
    t.uuid "organization_id", null: false
    t.jsonb "grouped_by", default: {}, null: false
    t.uuid "charge_filter_id"
    t.index ["billable_metric_id"], name: "index_quantified_events_on_billable_metric_id"
    t.index ["charge_filter_id"], name: "index_quantified_events_on_charge_filter_id"
    t.index ["deleted_at"], name: "index_quantified_events_on_deleted_at"
    t.index ["external_id"], name: "index_quantified_events_on_external_id"
    t.index ["group_id"], name: "index_quantified_events_on_group_id"
    t.index ["organization_id", "external_subscription_id", "billable_metric_id"], name: "index_search_quantified_events"
    t.index ["organization_id"], name: "index_quantified_events_on_organization_id"
  end

  create_table "recurring_transaction_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "wallet_id", null: false
    t.integer "trigger", default: 0, null: false
    t.decimal "paid_credits", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "granted_credits", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "threshold_credits", precision: 30, scale: 5, default: "0.0"
    t.integer "interval", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "method", default: 0, null: false
    t.decimal "target_ongoing_balance", precision: 30, scale: 5
    t.datetime "started_at"
    t.index ["started_at"], name: "index_recurring_transaction_rules_on_started_at"
    t.index ["wallet_id"], name: "index_recurring_transaction_rules_on_wallet_id"
  end

  create_table "refunds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "payment_id", null: false
    t.uuid "credit_note_id", null: false
    t.uuid "payment_provider_id"
    t.uuid "payment_provider_customer_id", null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "amount_currency", null: false
    t.string "status", null: false
    t.string "provider_refund_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["credit_note_id"], name: "index_refunds_on_credit_note_id"
    t.index ["payment_id"], name: "index_refunds_on_payment_id"
    t.index ["payment_provider_customer_id"], name: "index_refunds_on_payment_provider_customer_id"
    t.index ["payment_provider_id"], name: "index_refunds_on_payment_provider_id"
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
    t.string "name"
    t.string "external_id", null: false
    t.integer "billing_time", default: 0, null: false
    t.datetime "subscription_at"
    t.datetime "ending_at"
    t.datetime "trial_ended_at"
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["external_id"], name: "index_subscriptions_on_external_id"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["started_at", "ending_at"], name: "index_subscriptions_on_started_at_and_ending_at"
    t.index ["started_at"], name: "index_subscriptions_on_started_at"
    t.index ["status"], name: "index_subscriptions_on_status"
  end

  create_table "taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "description"
    t.string "code", null: false
    t.string "name", null: false
    t.float "rate", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "applied_to_organization", default: false, null: false
    t.boolean "auto_generated", default: false, null: false
    t.index ["code", "organization_id"], name: "index_taxes_on_code_and_organization_id", unique: true
    t.index ["organization_id"], name: "index_taxes_on_organization_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.string "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.jsonb "object"
    t.jsonb "object_changes"
    t.datetime "created_at"
    t.string "lago_version"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
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
    t.integer "source", default: 0, null: false
    t.integer "transaction_status", default: 0, null: false
    t.index ["invoice_id"], name: "index_wallet_transactions_on_invoice_id"
    t.index ["wallet_id"], name: "index_wallet_transactions_on_wallet_id"
  end

  create_table "wallets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.integer "status", null: false
    t.string "name"
    t.decimal "rate_amount", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "credits_balance", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "consumed_credits", precision: 30, scale: 5, default: "0.0", null: false
    t.datetime "expiration_at", precision: nil
    t.datetime "last_balance_sync_at", precision: nil
    t.datetime "last_consumed_credit_at", precision: nil
    t.datetime "terminated_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "balance_cents", default: 0, null: false
    t.string "balance_currency", null: false
    t.bigint "consumed_amount_cents", default: 0, null: false
    t.string "consumed_amount_currency", null: false
    t.bigint "ongoing_balance_cents", default: 0, null: false
    t.bigint "ongoing_usage_balance_cents", default: 0, null: false
    t.decimal "credits_ongoing_balance", precision: 30, scale: 5, default: "0.0", null: false
    t.decimal "credits_ongoing_usage_balance", precision: 30, scale: 5, default: "0.0", null: false
    t.boolean "depleted_ongoing_balance", default: false, null: false
    t.index ["customer_id"], name: "index_wallets_on_customer_id"
  end

  create_table "webhook_endpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "webhook_url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "signature_algo", default: 0, null: false
    t.index ["organization_id"], name: "index_webhook_endpoints_on_organization_id"
    t.index ["webhook_url", "organization_id"], name: "index_webhook_endpoints_on_webhook_url_and_organization_id", unique: true
  end

  create_table "webhooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "object_id"
    t.string "object_type"
    t.integer "status", default: 0, null: false
    t.integer "retries", default: 0, null: false
    t.integer "http_status"
    t.string "endpoint"
    t.string "webhook_type"
    t.json "payload"
    t.json "response"
    t.datetime "last_retried_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "webhook_endpoint_id"
    t.index ["webhook_endpoint_id"], name: "index_webhooks_on_webhook_endpoint_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "add_ons", "organizations"
  add_foreign_key "add_ons_taxes", "add_ons"
  add_foreign_key "add_ons_taxes", "taxes"
  add_foreign_key "adjusted_fees", "charges"
  add_foreign_key "adjusted_fees", "fees"
  add_foreign_key "adjusted_fees", "groups"
  add_foreign_key "adjusted_fees", "invoices"
  add_foreign_key "adjusted_fees", "subscriptions"
  add_foreign_key "applied_add_ons", "add_ons"
  add_foreign_key "applied_add_ons", "customers"
  add_foreign_key "billable_metric_filters", "billable_metrics"
  add_foreign_key "billable_metrics", "organizations"
  add_foreign_key "cached_aggregations", "groups"
  add_foreign_key "charge_filter_values", "billable_metric_filters"
  add_foreign_key "charge_filter_values", "charge_filters"
  add_foreign_key "charge_filters", "charges"
  add_foreign_key "charges", "billable_metrics"
  add_foreign_key "charges", "plans"
  add_foreign_key "charges_taxes", "charges"
  add_foreign_key "charges_taxes", "taxes"
  add_foreign_key "commitments", "plans"
  add_foreign_key "commitments_taxes", "commitments"
  add_foreign_key "commitments_taxes", "taxes"
  add_foreign_key "coupon_targets", "billable_metrics"
  add_foreign_key "coupon_targets", "coupons"
  add_foreign_key "coupon_targets", "plans"
  add_foreign_key "credit_note_items", "credit_notes"
  add_foreign_key "credit_note_items", "fees"
  add_foreign_key "credit_notes", "customers"
  add_foreign_key "credit_notes", "invoices"
  add_foreign_key "credit_notes_taxes", "credit_notes"
  add_foreign_key "credit_notes_taxes", "taxes"
  add_foreign_key "credits", "applied_coupons"
  add_foreign_key "credits", "credit_notes"
  add_foreign_key "credits", "invoices"
  add_foreign_key "customer_metadata", "customers"
  add_foreign_key "customers", "organizations"
  add_foreign_key "customers_taxes", "customers"
  add_foreign_key "customers_taxes", "taxes"
  add_foreign_key "data_exports", "memberships"
  add_foreign_key "data_exports", "organizations"
  add_foreign_key "fees", "add_ons"
  add_foreign_key "fees", "applied_add_ons"
  add_foreign_key "fees", "charges"
  add_foreign_key "fees", "fees", column: "true_up_parent_fee_id"
  add_foreign_key "fees", "groups"
  add_foreign_key "fees", "invoices"
  add_foreign_key "fees", "subscriptions"
  add_foreign_key "fees_taxes", "fees"
  add_foreign_key "fees_taxes", "taxes"
  add_foreign_key "group_properties", "charges", on_delete: :cascade
  add_foreign_key "group_properties", "groups", on_delete: :cascade
  add_foreign_key "groups", "billable_metrics", on_delete: :cascade
  add_foreign_key "groups", "groups", column: "parent_group_id"
  add_foreign_key "integration_collection_mappings", "integrations"
  add_foreign_key "integration_customers", "customers"
  add_foreign_key "integration_customers", "integrations"
  add_foreign_key "integration_items", "integrations"
  add_foreign_key "integration_mappings", "integrations"
  add_foreign_key "integration_resources", "integrations"
  add_foreign_key "integrations", "organizations"
  add_foreign_key "invites", "memberships"
  add_foreign_key "invites", "organizations"
  add_foreign_key "invoice_metadata", "invoices"
  add_foreign_key "invoice_subscriptions", "invoices"
  add_foreign_key "invoice_subscriptions", "subscriptions"
  add_foreign_key "invoices", "customers"
  add_foreign_key "invoices", "organizations"
  add_foreign_key "invoices_taxes", "invoices"
  add_foreign_key "invoices_taxes", "taxes"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "password_resets", "users"
  add_foreign_key "payment_provider_customers", "customers"
  add_foreign_key "payment_provider_customers", "payment_providers"
  add_foreign_key "payment_providers", "organizations"
  add_foreign_key "payments", "invoices"
  add_foreign_key "payments", "payment_providers"
  add_foreign_key "plans", "organizations"
  add_foreign_key "plans", "plans", column: "parent_id"
  add_foreign_key "plans_taxes", "plans"
  add_foreign_key "plans_taxes", "taxes"
  add_foreign_key "quantified_events", "groups"
  add_foreign_key "quantified_events", "organizations"
  add_foreign_key "recurring_transaction_rules", "wallets"
  add_foreign_key "refunds", "credit_notes"
  add_foreign_key "refunds", "payment_provider_customers"
  add_foreign_key "refunds", "payment_providers"
  add_foreign_key "refunds", "payments"
  add_foreign_key "subscriptions", "customers"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "taxes", "organizations"
  add_foreign_key "wallet_transactions", "invoices"
  add_foreign_key "wallet_transactions", "wallets"
  add_foreign_key "wallets", "customers"
  add_foreign_key "webhook_endpoints", "organizations"
  add_foreign_key "webhooks", "webhook_endpoints"

  create_view "last_hour_events_mv", materialized: true, sql_definition: <<-SQL
      WITH billable_metric_groups AS (
           SELECT billable_metrics_1.organization_id AS bm_organization_id,
              billable_metrics_1.id AS bm_id,
              billable_metrics_1.code AS bm_code,
              count(parent_groups.id) AS parent_group_count,
              array_agg(parent_groups.key) AS parent_group_keys,
              count(child_groups.id) AS child_group_count,
              array_agg(child_groups.key) AS child_group_keys
             FROM ((billable_metrics billable_metrics_1
               LEFT JOIN groups parent_groups ON (((parent_groups.billable_metric_id = billable_metrics_1.id) AND (parent_groups.parent_group_id IS NULL) AND (parent_groups.deleted_at IS NULL))))
               LEFT JOIN groups child_groups ON (((child_groups.billable_metric_id = billable_metrics_1.id) AND (child_groups.parent_group_id IS NOT NULL) AND (child_groups.deleted_at IS NULL))))
            WHERE (billable_metrics_1.deleted_at IS NULL)
            GROUP BY billable_metrics_1.id, billable_metrics_1.code
          ), billable_metric_filters AS (
           SELECT billable_metrics_1.organization_id AS bm_organization_id,
              billable_metrics_1.id AS bm_id,
              billable_metrics_1.code AS bm_code,
              filters.key AS filter_key,
              filters."values" AS filter_values
             FROM (billable_metrics billable_metrics_1
               JOIN public.billable_metric_filters filters ON ((filters.billable_metric_id = billable_metrics_1.id)))
            WHERE ((billable_metrics_1.deleted_at IS NULL) AND (filters.deleted_at IS NULL))
          )
   SELECT events.organization_id,
      events.transaction_id,
      events.properties,
      billable_metrics.code AS billable_metric_code,
      (billable_metrics.aggregation_type <> 0) AS field_name_mandatory,
      (billable_metrics.aggregation_type = ANY (ARRAY[1, 2, 5, 6])) AS numeric_field_mandatory,
      (events.properties ->> (billable_metrics.field_name)::text) AS field_value,
      ((events.properties ->> (billable_metrics.field_name)::text) ~ '^-?\\d+(\\.\\d+)?$'::text) AS is_numeric_field_value,
      (COALESCE(billable_metric_groups.parent_group_count, (0)::bigint) > 0) AS parent_group_mandatory,
      (events.properties ?| (billable_metric_groups.parent_group_keys)::text[]) AS has_parent_group_key,
      (COALESCE(billable_metric_groups.child_group_count, (0)::bigint) > 0) AS child_group_mandatory,
      (events.properties ?| (billable_metric_groups.child_group_keys)::text[]) AS has_child_group_key,
      (events.properties ? (billable_metric_filters.filter_key)::text) AS has_filter_keys,
      ((events.properties ->> (billable_metric_filters.filter_key)::text) = ANY ((billable_metric_filters.filter_values)::text[])) AS has_valid_filter_values
     FROM (((events
       LEFT JOIN billable_metrics ON ((((billable_metrics.code)::text = (events.code)::text) AND (events.organization_id = billable_metrics.organization_id))))
       LEFT JOIN billable_metric_groups ON ((billable_metrics.id = billable_metric_groups.bm_id)))
       LEFT JOIN billable_metric_filters ON ((billable_metrics.id = billable_metric_filters.bm_id)))
    WHERE ((events.deleted_at IS NULL) AND (events.created_at >= (date_trunc('hour'::text, now()) - 'PT1H'::interval)) AND (events.created_at < date_trunc('hour'::text, now())) AND (billable_metrics.deleted_at IS NULL));
  SQL
  add_index "last_hour_events_mv", ["organization_id"], name: "index_last_hour_events_mv_on_organization_id"

  create_view "billable_metrics_grouped_charges", sql_definition: <<-SQL
      SELECT billable_metrics.organization_id,
      billable_metrics.code,
      billable_metrics.aggregation_type,
      billable_metrics.field_name,
      charges.plan_id,
      charges.id AS charge_id,
          CASE
              WHEN (charges.charge_model = 0) THEN (charges.properties -> 'grouped_by'::text)
              ELSE NULL::jsonb
          END AS grouped_by,
      charge_filters.id AS charge_filter_id,
      json_object_agg(billable_metric_filters.key, COALESCE(charge_filter_values."values", '{}'::character varying[]) ORDER BY billable_metric_filters.key) FILTER (WHERE (billable_metric_filters.key IS NOT NULL)) AS filters,
          CASE
              WHEN (charges.charge_model = 0) THEN (charge_filters.properties -> 'grouped_by'::text)
              ELSE NULL::jsonb
          END AS filters_grouped_by
     FROM ((((billable_metrics
       JOIN charges ON ((charges.billable_metric_id = billable_metrics.id)))
       LEFT JOIN charge_filters ON ((charge_filters.charge_id = charges.id)))
       LEFT JOIN charge_filter_values ON ((charge_filter_values.charge_filter_id = charge_filters.id)))
       LEFT JOIN billable_metric_filters ON ((charge_filter_values.billable_metric_filter_id = billable_metric_filters.id)))
    WHERE ((billable_metrics.deleted_at IS NULL) AND (charges.deleted_at IS NULL) AND (charges.pay_in_advance = false) AND (charge_filters.deleted_at IS NULL) AND (charge_filter_values.deleted_at IS NULL) AND (billable_metric_filters.deleted_at IS NULL))
    GROUP BY billable_metrics.organization_id, billable_metrics.code, billable_metrics.aggregation_type, billable_metrics.field_name, charges.plan_id, charges.id, charge_filters.id;
  SQL
end
