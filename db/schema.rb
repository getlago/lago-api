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

ActiveRecord::Schema[7.0].define(version: 2023_09_18_090426) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "billable_metric_weighted_interval", ["seconds"]

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
    t.index ["deleted_at"], name: "index_billable_metrics_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_billable_metrics_on_organization_id_and_code", unique: true, where: "(deleted_at IS NULL)"
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
    t.datetime "deleted_at"
    t.boolean "pay_in_advance", default: false, null: false
    t.bigint "min_amount_cents", default: 0, null: false
    t.boolean "invoiceable", default: true, null: false
    t.boolean "prorated", default: false, null: false
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
    t.datetime "deleted_at"
    t.uuid "quantified_event_id"
    t.index ["customer_id"], name: "index_events_on_customer_id"
    t.index ["deleted_at"], name: "index_events_on_deleted_at"
    t.index ["organization_id", "code"], name: "index_events_on_organization_id_and_code"
    t.index ["organization_id"], name: "index_events_on_organization_id"
    t.index ["quantified_event_id"], name: "index_events_on_quantified_event_id"
    t.index ["subscription_id", "code", "timestamp"], name: "index_events_on_subscription_id_and_code_and_timestamp", where: "(deleted_at IS NULL)"
    t.index ["subscription_id", "transaction_id"], name: "index_events_on_subscription_id_and_transaction_id", unique: true
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
    t.index ["add_on_id"], name: "index_fees_on_add_on_id"
    t.index ["applied_add_on_id"], name: "index_fees_on_applied_add_on_id"
    t.index ["charge_id"], name: "index_fees_on_charge_id"
    t.index ["group_id"], name: "index_fees_on_group_id"
    t.index ["invoice_id"], name: "index_fees_on_invoice_id"
    t.index ["invoiceable_type", "invoiceable_id"], name: "index_fees_on_invoiceable"
    t.index ["subscription_id"], name: "index_fees_on_subscription_id"
    t.index ["true_up_parent_fee_id"], name: "index_fees_on_true_up_parent_fee_id"
  end

  create_table "fees_taxes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "fee_id", null: false
    t.uuid "tax_id", null: false
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
    t.index ["billable_metric_id"], name: "index_groups_on_billable_metric_id"
    t.index ["deleted_at"], name: "index_groups_on_deleted_at"
    t.index ["parent_group_id"], name: "index_groups_on_parent_group_id"
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

  create_table "invoice_metadata", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "invoice_id", null: false
    t.string "key", null: false
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "key"], name: "index_invoice_metadata_on_invoice_id_and_key", unique: true
    t.index ["invoice_id"], name: "index_invoice_metadata_on_invoice_id"
  end

