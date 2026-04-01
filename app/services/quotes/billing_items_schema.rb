# frozen_string_literal: true

module Quotes
  module BillingItemsSchema
    PLAN_SCHEMA = {
      "id" => {type: String},
      "position" => {type: Integer},
      "plan_code" => {type: String},
      "plan_id" => {type: String},
      "plan_name" => {type: String},
      "subscription_external_id" => {type: String}
    }.freeze

    COUPON_SCHEMA = {
      "id" => {type: String},
      "position" => {type: Integer},
      "coupon_id" => {type: String}
    }.freeze

    WALLET_CREDIT_SCHEMA = {
      "id" => {type: String},
      "position" => {type: Integer}
    }.freeze

    ADD_ON_SCHEMA = {
      "id" => {type: String},
      "position" => {type: Integer},
      "add_on_id" => {type: String},
      "add_on_code" => {type: String},
      "name" => {type: String},
      "units" => {type: Numeric},
      "amount_cents" => {type: Integer},
      "total_amount_cents" => {type: Integer}
    }.freeze

    PLAN_AMENDMENT_SCHEMA = PLAN_SCHEMA.merge(
      "subscription_external_id" => {type: String, required: true}
    ).freeze

    SUBSCRIPTION_CREATION_SCHEMA = {
      "plan" => {type: Hash, schema: PLAN_SCHEMA, required: true},
      "coupons" => {type: Array, items: {type: Hash, schema: COUPON_SCHEMA}},
      "wallet_credits" => {type: Array, items: {type: Hash, schema: WALLET_CREDIT_SCHEMA}}
    }.freeze

    SUBSCRIPTION_AMENDMENT_SCHEMA = {
      "plan" => {type: Hash, schema: PLAN_AMENDMENT_SCHEMA, required: true},
      "coupons" => {type: Array, items: {type: Hash, schema: COUPON_SCHEMA}},
      "wallet_credits" => {type: Array, items: {type: Hash, schema: WALLET_CREDIT_SCHEMA}}
    }.freeze

    ONE_OFF_SCHEMA = {
      "add_ons" => {type: Array, items: {type: Hash, schema: ADD_ON_SCHEMA}, required: true}
    }.freeze

    SCHEMAS_BY_ORDER_TYPE = {
      subscription_creation: SUBSCRIPTION_CREATION_SCHEMA,
      subscription_amendment: SUBSCRIPTION_AMENDMENT_SCHEMA,
      one_off: ONE_OFF_SCHEMA
    }.freeze
  end
end
