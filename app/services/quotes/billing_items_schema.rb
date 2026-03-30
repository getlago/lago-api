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
      "units" => {type: Integer},
      "amount_cents" => {type: Integer},
      "total_amount_cents" => {type: Integer}
    }.freeze

    BILLING_ITEMS_SCHEMA = {
      "plan" => {type: Hash, schema: PLAN_SCHEMA},
      "coupons" => {type: Array, items: {type: Hash, schema: COUPON_SCHEMA}},
      "wallet_credits" => {type: Array, items: {type: Hash, schema: WALLET_CREDIT_SCHEMA}},
      "add_ons" => {type: Array, items: {type: Hash, schema: ADD_ON_SCHEMA}}
    }.freeze
  end
end
