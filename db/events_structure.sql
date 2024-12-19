SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS fk_rails_fd399a23d3;
ALTER TABLE IF EXISTS ONLY public.fees_taxes DROP CONSTRAINT IF EXISTS fk_rails_f98413d404;
ALTER TABLE IF EXISTS ONLY public.quantified_events DROP CONSTRAINT IF EXISTS fk_rails_f510acb495;
ALTER TABLE IF EXISTS ONLY public.payment_requests DROP CONSTRAINT IF EXISTS fk_rails_f228550fda;
ALTER TABLE IF EXISTS ONLY public.customers_taxes DROP CONSTRAINT IF EXISTS fk_rails_ef731e48be;
ALTER TABLE IF EXISTS ONLY public.invoices_payment_requests DROP CONSTRAINT IF EXISTS fk_rails_ed387e0992;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_eaca9421be;
ALTER TABLE IF EXISTS ONLY public.integration_customers DROP CONSTRAINT IF EXISTS fk_rails_ea80151038;
ALTER TABLE IF EXISTS ONLY public.recurring_transaction_rules DROP CONSTRAINT IF EXISTS fk_rails_e8bac9c5bb;
ALTER TABLE IF EXISTS ONLY public.credit_note_items DROP CONSTRAINT IF EXISTS fk_rails_dea748e529;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_section_selections DROP CONSTRAINT IF EXISTS fk_rails_dd7e076158;
ALTER TABLE IF EXISTS ONLY public.invites DROP CONSTRAINT IF EXISTS fk_rails_dd342449a6;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_d9ffb8b4a1;
ALTER TABLE IF EXISTS ONLY public.coupon_targets DROP CONSTRAINT IF EXISTS fk_rails_d1dc5814e9;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS fk_rails_d07bc24ce3;
ALTER TABLE IF EXISTS ONLY public.integration_mappings DROP CONSTRAINT IF EXISTS fk_rails_cc318ad1ff;
ALTER TABLE IF EXISTS ONLY public.plans DROP CONSTRAINT IF EXISTS fk_rails_cbf700aeb8;
ALTER TABLE IF EXISTS ONLY public.invites DROP CONSTRAINT IF EXISTS fk_rails_c71f4b2026;
ALTER TABLE IF EXISTS ONLY public.active_storage_attachments DROP CONSTRAINT IF EXISTS fk_rails_c3b3935057;
ALTER TABLE IF EXISTS ONLY public.charge_filter_values DROP CONSTRAINT IF EXISTS fk_rails_bf661ef73d;
ALTER TABLE IF EXISTS ONLY public.dunning_campaign_thresholds DROP CONSTRAINT IF EXISTS fk_rails_bf1f386f75;
ALTER TABLE IF EXISTS ONLY public.plans_taxes DROP CONSTRAINT IF EXISTS fk_rails_bacde7a063;
ALTER TABLE IF EXISTS ONLY public.lifetime_usages DROP CONSTRAINT IF EXISTS fk_rails_ba128983c2;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_b50dc82c1e;
ALTER TABLE IF EXISTS ONLY public.daily_usages DROP CONSTRAINT IF EXISTS fk_rails_b07fc711f7;
ALTER TABLE IF EXISTS ONLY public.charges_taxes DROP CONSTRAINT IF EXISTS fk_rails_ac146c9541;
ALTER TABLE IF EXISTS ONLY public.commitments_taxes DROP CONSTRAINT IF EXISTS fk_rails_aaa12f7d3e;
ALTER TABLE IF EXISTS ONLY public.integration_items DROP CONSTRAINT IF EXISTS fk_rails_a9dc2ea536;
ALTER TABLE IF EXISTS ONLY public.charges DROP CONSTRAINT IF EXISTS fk_rails_a710519346;
ALTER TABLE IF EXISTS ONLY public.group_properties DROP CONSTRAINT IF EXISTS fk_rails_a2d2cb3819;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_section_selections DROP CONSTRAINT IF EXISTS fk_rails_9ff1d277f3;
ALTER TABLE IF EXISTS ONLY public.credit_note_items DROP CONSTRAINT IF EXISTS fk_rails_9f22076477;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS fk_rails_9ea6759859;
ALTER TABLE IF EXISTS ONLY public.applied_add_ons DROP CONSTRAINT IF EXISTS fk_rails_9c8e276cc0;
ALTER TABLE IF EXISTS ONLY public.plans_taxes DROP CONSTRAINT IF EXISTS fk_rails_9c704027e2;
ALTER TABLE IF EXISTS ONLY public.applied_usage_thresholds DROP CONSTRAINT IF EXISTS fk_rails_9c08b43701;
ALTER TABLE IF EXISTS ONLY public.active_storage_variant_records DROP CONSTRAINT IF EXISTS fk_rails_993965df05;
ALTER TABLE IF EXISTS ONLY public.memberships DROP CONSTRAINT IF EXISTS fk_rails_99326fb65d;
ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS fk_rails_98980b326b;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS fk_rails_94cc21031f;
ALTER TABLE IF EXISTS ONLY public.data_export_parts DROP CONSTRAINT IF EXISTS fk_rails_9298b8fdad;
ALTER TABLE IF EXISTS ONLY public.invoice_subscriptions DROP CONSTRAINT IF EXISTS fk_rails_90d93bd016;
ALTER TABLE IF EXISTS ONLY public.commitments_taxes DROP CONSTRAINT IF EXISTS fk_rails_8fa6f0d920;
ALTER TABLE IF EXISTS ONLY public.credits DROP CONSTRAINT IF EXISTS fk_rails_8ca834cd4a;
ALTER TABLE IF EXISTS ONLY public.invoice_metadata DROP CONSTRAINT IF EXISTS fk_rails_8bb5b094c4;
ALTER TABLE IF EXISTS ONLY public.add_ons_taxes DROP CONSTRAINT IF EXISTS fk_rails_89e1020aca;
ALTER TABLE IF EXISTS ONLY public.coupon_targets DROP CONSTRAINT IF EXISTS fk_rails_8872c07e0d;
ALTER TABLE IF EXISTS ONLY public.invoice_subscriptions DROP CONSTRAINT IF EXISTS fk_rails_88349fc20a;
ALTER TABLE IF EXISTS ONLY public.payment_provider_customers DROP CONSTRAINT IF EXISTS fk_rails_86676be631;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS fk_rails_84f4587409;
ALTER TABLE IF EXISTS ONLY public.add_ons DROP CONSTRAINT IF EXISTS fk_rails_81e3b6abba;
ALTER TABLE IF EXISTS ONLY public.charges DROP CONSTRAINT IF EXISTS fk_rails_7eb0484711;
ALTER TABLE IF EXISTS ONLY public.billable_metrics DROP CONSTRAINT IF EXISTS fk_rails_7e8a2f26e5;
ALTER TABLE IF EXISTS ONLY public.charge_filter_values DROP CONSTRAINT IF EXISTS fk_rails_7da558cadc;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_sections DROP CONSTRAINT IF EXISTS fk_rails_7c0e340dbd;
ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS fk_rails_7b324610ad;
ALTER TABLE IF EXISTS ONLY public.api_keys DROP CONSTRAINT IF EXISTS fk_rails_7aab96f30e;
ALTER TABLE IF EXISTS ONLY public.billable_metric_filters DROP CONSTRAINT IF EXISTS fk_rails_7a0704ce72;
ALTER TABLE IF EXISTS ONLY public.applied_add_ons DROP CONSTRAINT IF EXISTS fk_rails_7995206484;
ALTER TABLE IF EXISTS ONLY public.groups DROP CONSTRAINT IF EXISTS fk_rails_7886e1bc34;
ALTER TABLE IF EXISTS ONLY public.integrations DROP CONSTRAINT IF EXISTS fk_rails_755d734f25;
ALTER TABLE IF EXISTS ONLY public.refunds DROP CONSTRAINT IF EXISTS fk_rails_75577c354e;
ALTER TABLE IF EXISTS ONLY public.fees_taxes DROP CONSTRAINT IF EXISTS fk_rails_745b4ca7dd;
ALTER TABLE IF EXISTS ONLY public.data_exports DROP CONSTRAINT IF EXISTS fk_rails_73d83e23b6;
ALTER TABLE IF EXISTS ONLY public.invoices_taxes DROP CONSTRAINT IF EXISTS fk_rails_6e148ccbb1;
ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS fk_rails_6d465e6b10;
ALTER TABLE IF EXISTS ONLY public.dunning_campaigns DROP CONSTRAINT IF EXISTS fk_rails_6c720a8ccd;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_section_selections DROP CONSTRAINT IF EXISTS fk_rails_6b1e3d1159;
ALTER TABLE IF EXISTS ONLY public.integration_resources DROP CONSTRAINT IF EXISTS fk_rails_67d4eb3c92;
ALTER TABLE IF EXISTS ONLY public.subscriptions DROP CONSTRAINT IF EXISTS fk_rails_66eb6b32c1;
ALTER TABLE IF EXISTS ONLY public.taxes DROP CONSTRAINT IF EXISTS fk_rails_65b48ef6bf;
ALTER TABLE IF EXISTS ONLY public.memberships DROP CONSTRAINT IF EXISTS fk_rails_64267aab58;
ALTER TABLE IF EXISTS ONLY public.subscriptions DROP CONSTRAINT IF EXISTS fk_rails_63d3df128b;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS fk_rails_62d18ea517;
ALTER TABLE IF EXISTS ONLY public.credit_notes_taxes DROP CONSTRAINT IF EXISTS fk_rails_626209b8d2;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_6023b3f2dd;
ALTER TABLE IF EXISTS ONLY public.coupon_targets DROP CONSTRAINT IF EXISTS fk_rails_5fce5ea2b5;
ALTER TABLE IF EXISTS ONLY public.credit_notes DROP CONSTRAINT IF EXISTS fk_rails_5cb67dee79;
ALTER TABLE IF EXISTS ONLY public.error_details DROP CONSTRAINT IF EXISTS fk_rails_5c21eece29;
ALTER TABLE IF EXISTS ONLY public.data_exports DROP CONSTRAINT IF EXISTS fk_rails_5a43da571b;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS fk_rails_58234c715e;
ALTER TABLE IF EXISTS ONLY public.applied_usage_thresholds DROP CONSTRAINT IF EXISTS fk_rails_52b72c9b0e;
ALTER TABLE IF EXISTS ONLY public.password_resets DROP CONSTRAINT IF EXISTS fk_rails_526379cd99;
ALTER TABLE IF EXISTS ONLY public.credits DROP CONSTRAINT IF EXISTS fk_rails_521b5240ed;
ALTER TABLE IF EXISTS ONLY public.commitments DROP CONSTRAINT IF EXISTS fk_rails_51ac39a0c6;
ALTER TABLE IF EXISTS ONLY public.payment_provider_customers DROP CONSTRAINT IF EXISTS fk_rails_50d46d3679;
ALTER TABLE IF EXISTS ONLY public.usage_thresholds DROP CONSTRAINT IF EXISTS fk_rails_450b79f2a9;
ALTER TABLE IF EXISTS ONLY public.credit_notes DROP CONSTRAINT IF EXISTS fk_rails_4117574b51;
ALTER TABLE IF EXISTS ONLY public.charges_taxes DROP CONSTRAINT IF EXISTS fk_rails_3ff27d7624;
ALTER TABLE IF EXISTS ONLY public.refunds DROP CONSTRAINT IF EXISTS fk_rails_3f7be5debc;
ALTER TABLE IF EXISTS ONLY public.invoices_payment_requests DROP CONSTRAINT IF EXISTS fk_rails_3ec3563cf3;
ALTER TABLE IF EXISTS ONLY public.integration_collection_mappings DROP CONSTRAINT IF EXISTS fk_rails_3d568ff9de;
ALTER TABLE IF EXISTS ONLY public.charges DROP CONSTRAINT IF EXISTS fk_rails_3cfe1d68d7;
ALTER TABLE IF EXISTS ONLY public.daily_usages DROP CONSTRAINT IF EXISTS fk_rails_3c7c3920c0;
ALTER TABLE IF EXISTS ONLY public.group_properties DROP CONSTRAINT IF EXISTS fk_rails_3acf9e789c;
ALTER TABLE IF EXISTS ONLY public.invoices DROP CONSTRAINT IF EXISTS fk_rails_3a303bf667;
ALTER TABLE IF EXISTS ONLY public.quantified_events DROP CONSTRAINT IF EXISTS fk_rails_3926855f12;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_38047eb662;
ALTER TABLE IF EXISTS ONLY public.customers_taxes DROP CONSTRAINT IF EXISTS fk_rails_3708a65be3;
ALTER TABLE IF EXISTS ONLY public.groups DROP CONSTRAINT IF EXISTS fk_rails_34b5ee1894;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_34ab152115;
ALTER TABLE IF EXISTS ONLY public.lifetime_usages DROP CONSTRAINT IF EXISTS fk_rails_348acbd245;
ALTER TABLE IF EXISTS ONLY public.payment_requests DROP CONSTRAINT IF EXISTS fk_rails_32600e5a72;
ALTER TABLE IF EXISTS ONLY public.credits DROP CONSTRAINT IF EXISTS fk_rails_2fd7ee65e6;
ALTER TABLE IF EXISTS ONLY public.payment_requests DROP CONSTRAINT IF EXISTS fk_rails_2fb2147151;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_2ea4db3a4c;
ALTER TABLE IF EXISTS ONLY public.refunds DROP CONSTRAINT IF EXISTS fk_rails_2dc6171f57;
ALTER TABLE IF EXISTS ONLY public.wallets DROP CONSTRAINT IF EXISTS fk_rails_2b35eef34b;
ALTER TABLE IF EXISTS ONLY public.charge_filters DROP CONSTRAINT IF EXISTS fk_rails_27b55b8574;
ALTER TABLE IF EXISTS ONLY public.payment_providers DROP CONSTRAINT IF EXISTS fk_rails_26be2f764d;
ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS fk_rails_2561c00887;
ALTER TABLE IF EXISTS ONLY public.refunds DROP CONSTRAINT IF EXISTS fk_rails_25267b0e17;
ALTER TABLE IF EXISTS ONLY public.credit_notes_taxes DROP CONSTRAINT IF EXISTS fk_rails_25232a0ec3;
ALTER TABLE IF EXISTS ONLY public.invoices_taxes DROP CONSTRAINT IF EXISTS fk_rails_22af6c6d28;
ALTER TABLE IF EXISTS ONLY public.cached_aggregations DROP CONSTRAINT IF EXISTS fk_rails_21eb389927;
ALTER TABLE IF EXISTS ONLY public.webhook_endpoints DROP CONSTRAINT IF EXISTS fk_rails_21808fa528;
ALTER TABLE IF EXISTS ONLY public.plans DROP CONSTRAINT IF EXISTS fk_rails_216ac8a975;
ALTER TABLE IF EXISTS ONLY public.webhooks DROP CONSTRAINT IF EXISTS fk_rails_20cc0de4c7;
ALTER TABLE IF EXISTS ONLY public.credits DROP CONSTRAINT IF EXISTS fk_rails_1db0057d9b;
ALTER TABLE IF EXISTS ONLY public.customer_metadata DROP CONSTRAINT IF EXISTS fk_rails_195153290d;
ALTER TABLE IF EXISTS ONLY public.daily_usages DROP CONSTRAINT IF EXISTS fk_rails_12d29bc654;
ALTER TABLE IF EXISTS ONLY public.applied_invoice_custom_sections DROP CONSTRAINT IF EXISTS fk_rails_10428ecad2;
ALTER TABLE IF EXISTS ONLY public.integration_customers DROP CONSTRAINT IF EXISTS fk_rails_0e464363cb;
ALTER TABLE IF EXISTS ONLY public.invoices DROP CONSTRAINT IF EXISTS fk_rails_0d349e632f;
ALTER TABLE IF EXISTS ONLY public.add_ons_taxes DROP CONSTRAINT IF EXISTS fk_rails_08dfe87131;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fk_rails_085d1cc97b;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS fk_rails_01a4c0c7db;
CREATE OR REPLACE VIEW public.billable_metrics_grouped_charges AS
SELECT
    NULL::uuid AS organization_id,
    NULL::character varying AS code,
    NULL::integer AS aggregation_type,
    NULL::character varying AS field_name,
    NULL::uuid AS plan_id,
    NULL::uuid AS charge_id,
    NULL::boolean AS pay_in_advance,
    NULL::jsonb AS grouped_by,
    NULL::uuid AS charge_filter_id,
    NULL::json AS filters,
    NULL::jsonb AS filters_grouped_by;
DROP INDEX IF EXISTS public.index_webhooks_on_webhook_endpoint_id;
DROP INDEX IF EXISTS public.index_webhook_endpoints_on_webhook_url_and_organization_id;
DROP INDEX IF EXISTS public.index_webhook_endpoints_on_organization_id;
DROP INDEX IF EXISTS public.index_wallets_on_ready_to_be_refreshed;
DROP INDEX IF EXISTS public.index_wallets_on_customer_id;
DROP INDEX IF EXISTS public.index_wallet_transactions_on_wallet_id;
DROP INDEX IF EXISTS public.index_wallet_transactions_on_invoice_id;
DROP INDEX IF EXISTS public.index_wallet_transactions_on_credit_note_id;
DROP INDEX IF EXISTS public.index_versions_on_item_type_and_item_id;
DROP INDEX IF EXISTS public.index_usage_thresholds_on_plan_id_and_recurring;
DROP INDEX IF EXISTS public.index_usage_thresholds_on_plan_id;
DROP INDEX IF EXISTS public.index_unique_transaction_id;
DROP INDEX IF EXISTS public.index_unique_terminating_subscription_invoice;
DROP INDEX IF EXISTS public.index_unique_starting_subscription_invoice;
DROP INDEX IF EXISTS public.index_unique_applied_to_organization_per_organization;
DROP INDEX IF EXISTS public.index_timestamp_lookup;
DROP INDEX IF EXISTS public.index_timestamp_group_lookup;
DROP INDEX IF EXISTS public.index_timestamp_filter_lookup;
DROP INDEX IF EXISTS public.index_taxes_on_organization_id;
DROP INDEX IF EXISTS public.index_taxes_on_code_and_organization_id;
DROP INDEX IF EXISTS public.index_subscriptions_on_status;
DROP INDEX IF EXISTS public.index_subscriptions_on_started_at_and_ending_at;
DROP INDEX IF EXISTS public.index_subscriptions_on_started_at;
DROP INDEX IF EXISTS public.index_subscriptions_on_previous_subscription_id_and_status;
DROP INDEX IF EXISTS public.index_subscriptions_on_plan_id;
DROP INDEX IF EXISTS public.index_subscriptions_on_external_id;
DROP INDEX IF EXISTS public.index_subscriptions_on_customer_id;
DROP INDEX IF EXISTS public.index_search_quantified_events;
DROP INDEX IF EXISTS public.index_refunds_on_payment_provider_id;
DROP INDEX IF EXISTS public.index_refunds_on_payment_provider_customer_id;
DROP INDEX IF EXISTS public.index_refunds_on_payment_id;
DROP INDEX IF EXISTS public.index_refunds_on_credit_note_id;
DROP INDEX IF EXISTS public.index_recurring_transaction_rules_on_wallet_id;
DROP INDEX IF EXISTS public.index_recurring_transaction_rules_on_started_at;
DROP INDEX IF EXISTS public.index_quantified_events_on_organization_id;
DROP INDEX IF EXISTS public.index_quantified_events_on_group_id;
DROP INDEX IF EXISTS public.index_quantified_events_on_external_id;
DROP INDEX IF EXISTS public.index_quantified_events_on_deleted_at;
DROP INDEX IF EXISTS public.index_quantified_events_on_charge_filter_id;
DROP INDEX IF EXISTS public.index_quantified_events_on_billable_metric_id;
DROP INDEX IF EXISTS public.index_plans_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_plans_taxes_on_plan_id_and_tax_id;
DROP INDEX IF EXISTS public.index_plans_taxes_on_plan_id;
DROP INDEX IF EXISTS public.index_plans_on_parent_id;
DROP INDEX IF EXISTS public.index_plans_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_plans_on_organization_id;
DROP INDEX IF EXISTS public.index_plans_on_deleted_at;
DROP INDEX IF EXISTS public.index_plans_on_created_at;
DROP INDEX IF EXISTS public.index_payments_on_payment_provider_id;
DROP INDEX IF EXISTS public.index_payments_on_payment_provider_customer_id;
DROP INDEX IF EXISTS public.index_payments_on_payable_type_and_payable_id;
DROP INDEX IF EXISTS public.index_payments_on_payable_id_and_payable_type;
DROP INDEX IF EXISTS public.index_payments_on_invoice_id;
DROP INDEX IF EXISTS public.index_payment_requests_on_organization_id;
DROP INDEX IF EXISTS public.index_payment_requests_on_dunning_campaign_id;
DROP INDEX IF EXISTS public.index_payment_requests_on_customer_id;
DROP INDEX IF EXISTS public.index_payment_providers_on_organization_id;
DROP INDEX IF EXISTS public.index_payment_providers_on_code_and_organization_id;
DROP INDEX IF EXISTS public.index_payment_provider_customers_on_provider_customer_id;
DROP INDEX IF EXISTS public.index_payment_provider_customers_on_payment_provider_id;
DROP INDEX IF EXISTS public.index_payment_provider_customers_on_customer_id_and_type;
DROP INDEX IF EXISTS public.index_password_resets_on_user_id;
DROP INDEX IF EXISTS public.index_password_resets_on_token;
DROP INDEX IF EXISTS public.index_organizations_on_hmac_key;
DROP INDEX IF EXISTS public.index_organizations_on_api_key;
DROP INDEX IF EXISTS public.index_memberships_on_user_id_and_organization_id;
DROP INDEX IF EXISTS public.index_memberships_on_user_id;
DROP INDEX IF EXISTS public.index_memberships_on_organization_id;
DROP INDEX IF EXISTS public.index_lifetime_usages_on_subscription_id;
DROP INDEX IF EXISTS public.index_lifetime_usages_on_recalculate_invoiced_usage;
DROP INDEX IF EXISTS public.index_lifetime_usages_on_recalculate_current_usage;
DROP INDEX IF EXISTS public.index_lifetime_usages_on_organization_id;
DROP INDEX IF EXISTS public.index_invoices_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_invoices_taxes_on_invoice_id_and_tax_id;
DROP INDEX IF EXISTS public.index_invoices_taxes_on_invoice_id;
DROP INDEX IF EXISTS public.index_invoices_payment_requests_on_payment_request_id;
DROP INDEX IF EXISTS public.index_invoices_payment_requests_on_invoice_id;
DROP INDEX IF EXISTS public.index_invoices_on_status;
DROP INDEX IF EXISTS public.index_invoices_on_sequential_id;
DROP INDEX IF EXISTS public.index_invoices_on_payment_overdue;
DROP INDEX IF EXISTS public.index_invoices_on_organization_id;
DROP INDEX IF EXISTS public.index_invoices_on_number;
DROP INDEX IF EXISTS public.index_invoices_on_customer_id_and_sequential_id;
DROP INDEX IF EXISTS public.index_invoices_on_customer_id;
DROP INDEX IF EXISTS public.index_invoice_subscriptions_on_subscription_id;
DROP INDEX IF EXISTS public.index_invoice_subscriptions_on_invoice_id_and_subscription_id;
DROP INDEX IF EXISTS public.index_invoice_subscriptions_on_invoice_id;
DROP INDEX IF EXISTS public.index_invoice_subscriptions_on_charges_from_and_to_datetime;
DROP INDEX IF EXISTS public.index_invoice_subscriptions_boundaries;
DROP INDEX IF EXISTS public.index_invoice_metadata_on_invoice_id_and_key;
DROP INDEX IF EXISTS public.index_invoice_metadata_on_invoice_id;
DROP INDEX IF EXISTS public.index_invoice_custom_sections_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_invoice_custom_sections_on_organization_id;
DROP INDEX IF EXISTS public.index_invoice_custom_section_selections_on_organization_id;
DROP INDEX IF EXISTS public.index_invoice_custom_section_selections_on_customer_id;
DROP INDEX IF EXISTS public.index_invites_on_token;
DROP INDEX IF EXISTS public.index_invites_on_organization_id;
DROP INDEX IF EXISTS public.index_invites_on_membership_id;
DROP INDEX IF EXISTS public.index_integrations_on_organization_id;
DROP INDEX IF EXISTS public.index_integrations_on_code_and_organization_id;
DROP INDEX IF EXISTS public.index_integration_resources_on_syncable;
DROP INDEX IF EXISTS public.index_integration_resources_on_integration_id;
DROP INDEX IF EXISTS public.index_integration_mappings_on_mappable;
DROP INDEX IF EXISTS public.index_integration_mappings_on_integration_id;
DROP INDEX IF EXISTS public.index_integration_items_on_integration_id;
DROP INDEX IF EXISTS public.index_integration_customers_on_integration_id;
DROP INDEX IF EXISTS public.index_integration_customers_on_external_customer_id;
DROP INDEX IF EXISTS public.index_integration_customers_on_customer_id_and_type;
DROP INDEX IF EXISTS public.index_integration_customers_on_customer_id;
DROP INDEX IF EXISTS public.index_integration_collection_mappings_on_integration_id;
DROP INDEX IF EXISTS public.index_int_items_on_external_id_and_int_id_and_type;
DROP INDEX IF EXISTS public.index_int_collection_mappings_on_mapping_type_and_int_id;
DROP INDEX IF EXISTS public.index_groups_on_parent_group_id;
DROP INDEX IF EXISTS public.index_groups_on_deleted_at;
DROP INDEX IF EXISTS public.index_groups_on_billable_metric_id_and_parent_group_id;
DROP INDEX IF EXISTS public.index_groups_on_billable_metric_id;
DROP INDEX IF EXISTS public.index_group_properties_on_group_id;
DROP INDEX IF EXISTS public.index_group_properties_on_deleted_at;
DROP INDEX IF EXISTS public.index_group_properties_on_charge_id_and_group_id;
DROP INDEX IF EXISTS public.index_group_properties_on_charge_id;
DROP INDEX IF EXISTS public.index_fees_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_fees_taxes_on_fee_id_and_tax_id;
DROP INDEX IF EXISTS public.index_fees_taxes_on_fee_id;
DROP INDEX IF EXISTS public.index_fees_on_true_up_parent_fee_id;
DROP INDEX IF EXISTS public.index_fees_on_subscription_id;
DROP INDEX IF EXISTS public.index_fees_on_pay_in_advance_event_transaction_id;
DROP INDEX IF EXISTS public.index_fees_on_organization_id;
DROP INDEX IF EXISTS public.index_fees_on_invoiceable;
DROP INDEX IF EXISTS public.index_fees_on_invoice_id;
DROP INDEX IF EXISTS public.index_fees_on_group_id;
DROP INDEX IF EXISTS public.index_fees_on_deleted_at;
DROP INDEX IF EXISTS public.index_fees_on_charge_id_and_invoice_id;
DROP INDEX IF EXISTS public.index_fees_on_charge_id;
DROP INDEX IF EXISTS public.index_fees_on_charge_filter_id;
DROP INDEX IF EXISTS public.index_fees_on_applied_add_on_id;
DROP INDEX IF EXISTS public.index_fees_on_add_on_id;
DROP INDEX IF EXISTS public.index_events_on_subscription_id_and_code_and_timestamp;
DROP INDEX IF EXISTS public.index_events_on_subscription_id;
DROP INDEX IF EXISTS public.index_events_on_properties;
DROP INDEX IF EXISTS public.index_events_on_organization_id_and_timestamp;
DROP INDEX IF EXISTS public.index_events_on_organization_id_and_code_and_created_at;
DROP INDEX IF EXISTS public.index_events_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_events_on_organization_id;
DROP INDEX IF EXISTS public.index_events_on_external_subscription_id_with_included;
DROP INDEX IF EXISTS public.index_events_on_external_subscription_id_precise_amount;
DROP INDEX IF EXISTS public.index_events_on_external_subscription_id_and_code_and_timestamp;
DROP INDEX IF EXISTS public.index_events_on_deleted_at;
DROP INDEX IF EXISTS public.index_events_on_customer_id;
DROP INDEX IF EXISTS public.index_error_details_on_owner;
DROP INDEX IF EXISTS public.index_error_details_on_organization_id;
DROP INDEX IF EXISTS public.index_error_details_on_error_code;
DROP INDEX IF EXISTS public.index_error_details_on_deleted_at;
DROP INDEX IF EXISTS public.index_dunning_campaigns_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_dunning_campaigns_on_organization_id;
DROP INDEX IF EXISTS public.index_dunning_campaigns_on_deleted_at;
DROP INDEX IF EXISTS public.index_dunning_campaign_thresholds_on_dunning_campaign_id;
DROP INDEX IF EXISTS public.index_dunning_campaign_thresholds_on_deleted_at;
DROP INDEX IF EXISTS public.index_data_exports_on_organization_id;
DROP INDEX IF EXISTS public.index_data_exports_on_membership_id;
DROP INDEX IF EXISTS public.index_data_export_parts_on_data_export_id;
DROP INDEX IF EXISTS public.index_daily_usages_on_subscription_id;
DROP INDEX IF EXISTS public.index_daily_usages_on_organization_id;
DROP INDEX IF EXISTS public.index_daily_usages_on_customer_id;
DROP INDEX IF EXISTS public.index_customers_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_customers_taxes_on_customer_id_and_tax_id;
DROP INDEX IF EXISTS public.index_customers_taxes_on_customer_id;
DROP INDEX IF EXISTS public.index_customers_on_organization_id;
DROP INDEX IF EXISTS public.index_customers_on_external_id_and_organization_id;
DROP INDEX IF EXISTS public.index_customers_on_deleted_at;
DROP INDEX IF EXISTS public.index_customers_on_applied_dunning_campaign_id;
DROP INDEX IF EXISTS public.index_customer_metadata_on_customer_id_and_key;
DROP INDEX IF EXISTS public.index_customer_metadata_on_customer_id;
DROP INDEX IF EXISTS public.index_credits_on_progressive_billing_invoice_id;
DROP INDEX IF EXISTS public.index_credits_on_invoice_id;
DROP INDEX IF EXISTS public.index_credits_on_credit_note_id;
DROP INDEX IF EXISTS public.index_credits_on_applied_coupon_id;
DROP INDEX IF EXISTS public.index_credit_notes_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_credit_notes_taxes_on_tax_code;
DROP INDEX IF EXISTS public.index_credit_notes_taxes_on_credit_note_id_and_tax_code;
DROP INDEX IF EXISTS public.index_credit_notes_taxes_on_credit_note_id;
DROP INDEX IF EXISTS public.index_credit_notes_on_invoice_id;
DROP INDEX IF EXISTS public.index_credit_notes_on_customer_id;
DROP INDEX IF EXISTS public.index_credit_note_items_on_fee_id;
DROP INDEX IF EXISTS public.index_credit_note_items_on_credit_note_id;
DROP INDEX IF EXISTS public.index_coupons_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_coupons_on_organization_id;
DROP INDEX IF EXISTS public.index_coupons_on_deleted_at;
DROP INDEX IF EXISTS public.index_coupon_targets_on_plan_id;
DROP INDEX IF EXISTS public.index_coupon_targets_on_deleted_at;
DROP INDEX IF EXISTS public.index_coupon_targets_on_coupon_id;
DROP INDEX IF EXISTS public.index_coupon_targets_on_billable_metric_id;
DROP INDEX IF EXISTS public.index_commitments_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_commitments_taxes_on_commitment_id;
DROP INDEX IF EXISTS public.index_commitments_on_plan_id;
DROP INDEX IF EXISTS public.index_commitments_on_commitment_type_and_plan_id;
DROP INDEX IF EXISTS public.index_charges_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_charges_taxes_on_charge_id_and_tax_id;
DROP INDEX IF EXISTS public.index_charges_taxes_on_charge_id;
DROP INDEX IF EXISTS public.index_charges_on_plan_id;
DROP INDEX IF EXISTS public.index_charges_on_parent_id;
DROP INDEX IF EXISTS public.index_charges_on_deleted_at;
DROP INDEX IF EXISTS public.index_charges_on_billable_metric_id;
DROP INDEX IF EXISTS public.index_charge_filters_on_deleted_at;
DROP INDEX IF EXISTS public.index_charge_filters_on_charge_id;
DROP INDEX IF EXISTS public.index_charge_filter_values_on_deleted_at;
DROP INDEX IF EXISTS public.index_charge_filter_values_on_charge_filter_id;
DROP INDEX IF EXISTS public.index_charge_filter_values_on_billable_metric_filter_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_organization_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_group_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_external_subscription_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_event_transaction_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_event_id;
DROP INDEX IF EXISTS public.index_cached_aggregations_on_charge_id;
DROP INDEX IF EXISTS public.index_billable_metrics_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_billable_metrics_on_organization_id;
DROP INDEX IF EXISTS public.index_billable_metrics_on_org_id_and_code_and_expr;
DROP INDEX IF EXISTS public.index_billable_metrics_on_deleted_at;
DROP INDEX IF EXISTS public.index_billable_metric_filters_on_deleted_at;
DROP INDEX IF EXISTS public.index_billable_metric_filters_on_billable_metric_id;
DROP INDEX IF EXISTS public.index_applied_usage_thresholds_on_usage_threshold_id;
DROP INDEX IF EXISTS public.index_applied_usage_thresholds_on_invoice_id;
DROP INDEX IF EXISTS public.index_applied_invoice_custom_sections_on_invoice_id;
DROP INDEX IF EXISTS public.index_applied_coupons_on_customer_id;
DROP INDEX IF EXISTS public.index_applied_coupons_on_coupon_id;
DROP INDEX IF EXISTS public.index_applied_add_ons_on_customer_id;
DROP INDEX IF EXISTS public.index_applied_add_ons_on_add_on_id_and_customer_id;
DROP INDEX IF EXISTS public.index_applied_add_ons_on_add_on_id;
DROP INDEX IF EXISTS public.index_api_keys_on_value;
DROP INDEX IF EXISTS public.index_api_keys_on_organization_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_subscription_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_invoice_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_group_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_fee_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_charge_id;
DROP INDEX IF EXISTS public.index_adjusted_fees_on_charge_filter_id;
DROP INDEX IF EXISTS public.index_add_ons_taxes_on_tax_id;
DROP INDEX IF EXISTS public.index_add_ons_taxes_on_add_on_id_and_tax_id;
DROP INDEX IF EXISTS public.index_add_ons_taxes_on_add_on_id;
DROP INDEX IF EXISTS public.index_add_ons_on_organization_id_and_code;
DROP INDEX IF EXISTS public.index_add_ons_on_organization_id;
DROP INDEX IF EXISTS public.index_add_ons_on_deleted_at;
DROP INDEX IF EXISTS public.index_active_storage_variant_records_uniqueness;
DROP INDEX IF EXISTS public.index_active_storage_blobs_on_key;
DROP INDEX IF EXISTS public.index_active_storage_attachments_uniqueness;
DROP INDEX IF EXISTS public.index_active_storage_attachments_on_blob_id;
DROP INDEX IF EXISTS public.index_active_metric_filters;
DROP INDEX IF EXISTS public.index_active_charge_filters;
DROP INDEX IF EXISTS public.index_active_charge_filter_values;
DROP INDEX IF EXISTS public.idx_on_usage_threshold_id_invoice_id_cb82cdf163;
DROP INDEX IF EXISTS public.idx_on_start_processing_at_external_subscription_id_31b81116ce;
DROP INDEX IF EXISTS public.idx_on_organization_id_external_subscription_id_df3a30d96d;
DROP INDEX IF EXISTS public.idx_on_organization_id_deleted_at_225e3f789d;
DROP INDEX IF EXISTS public.idx_on_invoice_id_payment_request_id_aa550779a4;
DROP INDEX IF EXISTS public.idx_on_invoice_custom_section_id_7edbcef7b5;
DROP INDEX IF EXISTS public.idx_on_external_subscription_id_organization_id_40aa74e2eb;
DROP INDEX IF EXISTS public.idx_on_dunning_campaign_id_currency_fbf233b2ae;
DROP INDEX IF EXISTS public.idx_on_amount_cents_plan_id_recurring_888044d66b;
ALTER TABLE IF EXISTS ONLY public.webhooks DROP CONSTRAINT IF EXISTS webhooks_pkey;
ALTER TABLE IF EXISTS ONLY public.webhook_endpoints DROP CONSTRAINT IF EXISTS webhook_endpoints_pkey;
ALTER TABLE IF EXISTS ONLY public.wallets DROP CONSTRAINT IF EXISTS wallets_pkey;
ALTER TABLE IF EXISTS ONLY public.wallet_transactions DROP CONSTRAINT IF EXISTS wallet_transactions_pkey;
ALTER TABLE IF EXISTS ONLY public.versions DROP CONSTRAINT IF EXISTS versions_pkey;
ALTER TABLE IF EXISTS ONLY public.users DROP CONSTRAINT IF EXISTS users_pkey;
ALTER TABLE IF EXISTS ONLY public.usage_thresholds DROP CONSTRAINT IF EXISTS usage_thresholds_pkey;
ALTER TABLE IF EXISTS ONLY public.taxes DROP CONSTRAINT IF EXISTS taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.subscriptions DROP CONSTRAINT IF EXISTS subscriptions_pkey;
ALTER TABLE IF EXISTS ONLY public.subscription_event_triggers DROP CONSTRAINT IF EXISTS subscription_event_triggers_pkey;
ALTER TABLE IF EXISTS ONLY public.schema_migrations DROP CONSTRAINT IF EXISTS schema_migrations_pkey;
ALTER TABLE IF EXISTS ONLY public.refunds DROP CONSTRAINT IF EXISTS refunds_pkey;
ALTER TABLE IF EXISTS ONLY public.recurring_transaction_rules DROP CONSTRAINT IF EXISTS recurring_transaction_rules_pkey;
ALTER TABLE IF EXISTS ONLY public.quantified_events DROP CONSTRAINT IF EXISTS quantified_events_pkey;
ALTER TABLE IF EXISTS ONLY public.plans_taxes DROP CONSTRAINT IF EXISTS plans_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.plans DROP CONSTRAINT IF EXISTS plans_pkey;
ALTER TABLE IF EXISTS ONLY public.payments DROP CONSTRAINT IF EXISTS payments_pkey;
ALTER TABLE IF EXISTS ONLY public.payment_requests DROP CONSTRAINT IF EXISTS payment_requests_pkey;
ALTER TABLE IF EXISTS ONLY public.payment_providers DROP CONSTRAINT IF EXISTS payment_providers_pkey;
ALTER TABLE IF EXISTS ONLY public.payment_provider_customers DROP CONSTRAINT IF EXISTS payment_provider_customers_pkey;
ALTER TABLE IF EXISTS ONLY public.password_resets DROP CONSTRAINT IF EXISTS password_resets_pkey;
ALTER TABLE IF EXISTS ONLY public.organizations DROP CONSTRAINT IF EXISTS organizations_pkey;
ALTER TABLE IF EXISTS ONLY public.memberships DROP CONSTRAINT IF EXISTS memberships_pkey;
ALTER TABLE IF EXISTS ONLY public.lifetime_usages DROP CONSTRAINT IF EXISTS lifetime_usages_pkey;
ALTER TABLE IF EXISTS ONLY public.invoices_taxes DROP CONSTRAINT IF EXISTS invoices_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.invoices DROP CONSTRAINT IF EXISTS invoices_pkey;
ALTER TABLE IF EXISTS ONLY public.invoices_payment_requests DROP CONSTRAINT IF EXISTS invoices_payment_requests_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_subscriptions DROP CONSTRAINT IF EXISTS invoice_subscriptions_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_metadata DROP CONSTRAINT IF EXISTS invoice_metadata_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_errors DROP CONSTRAINT IF EXISTS invoice_errors_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_sections DROP CONSTRAINT IF EXISTS invoice_custom_sections_pkey;
ALTER TABLE IF EXISTS ONLY public.invoice_custom_section_selections DROP CONSTRAINT IF EXISTS invoice_custom_section_selections_pkey;
ALTER TABLE IF EXISTS ONLY public.invites DROP CONSTRAINT IF EXISTS invites_pkey;
ALTER TABLE IF EXISTS ONLY public.integrations DROP CONSTRAINT IF EXISTS integrations_pkey;
ALTER TABLE IF EXISTS ONLY public.integration_resources DROP CONSTRAINT IF EXISTS integration_resources_pkey;
ALTER TABLE IF EXISTS ONLY public.integration_mappings DROP CONSTRAINT IF EXISTS integration_mappings_pkey;
ALTER TABLE IF EXISTS ONLY public.integration_items DROP CONSTRAINT IF EXISTS integration_items_pkey;
ALTER TABLE IF EXISTS ONLY public.integration_customers DROP CONSTRAINT IF EXISTS integration_customers_pkey;
ALTER TABLE IF EXISTS ONLY public.integration_collection_mappings DROP CONSTRAINT IF EXISTS integration_collection_mappings_pkey;
ALTER TABLE IF EXISTS ONLY public.groups DROP CONSTRAINT IF EXISTS groups_pkey;
ALTER TABLE IF EXISTS ONLY public.group_properties DROP CONSTRAINT IF EXISTS group_properties_pkey;
ALTER TABLE IF EXISTS ONLY public.fees_taxes DROP CONSTRAINT IF EXISTS fees_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.fees DROP CONSTRAINT IF EXISTS fees_pkey;
ALTER TABLE IF EXISTS ONLY public.events DROP CONSTRAINT IF EXISTS events_pkey;
ALTER TABLE IF EXISTS ONLY public.error_details DROP CONSTRAINT IF EXISTS error_details_pkey;
ALTER TABLE IF EXISTS ONLY public.dunning_campaigns DROP CONSTRAINT IF EXISTS dunning_campaigns_pkey;
ALTER TABLE IF EXISTS ONLY public.dunning_campaign_thresholds DROP CONSTRAINT IF EXISTS dunning_campaign_thresholds_pkey;
ALTER TABLE IF EXISTS ONLY public.data_exports DROP CONSTRAINT IF EXISTS data_exports_pkey;
ALTER TABLE IF EXISTS ONLY public.data_export_parts DROP CONSTRAINT IF EXISTS data_export_parts_pkey;
ALTER TABLE IF EXISTS ONLY public.daily_usages DROP CONSTRAINT IF EXISTS daily_usages_pkey;
ALTER TABLE IF EXISTS ONLY public.customers_taxes DROP CONSTRAINT IF EXISTS customers_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.customers DROP CONSTRAINT IF EXISTS customers_pkey;
ALTER TABLE IF EXISTS ONLY public.customer_metadata DROP CONSTRAINT IF EXISTS customer_metadata_pkey;
ALTER TABLE IF EXISTS ONLY public.credits DROP CONSTRAINT IF EXISTS credits_pkey;
ALTER TABLE IF EXISTS ONLY public.credit_notes_taxes DROP CONSTRAINT IF EXISTS credit_notes_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.credit_notes DROP CONSTRAINT IF EXISTS credit_notes_pkey;
ALTER TABLE IF EXISTS ONLY public.credit_note_items DROP CONSTRAINT IF EXISTS credit_note_items_pkey;
ALTER TABLE IF EXISTS ONLY public.coupons DROP CONSTRAINT IF EXISTS coupons_pkey;
ALTER TABLE IF EXISTS ONLY public.coupon_targets DROP CONSTRAINT IF EXISTS coupon_targets_pkey;
ALTER TABLE IF EXISTS ONLY public.commitments_taxes DROP CONSTRAINT IF EXISTS commitments_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.commitments DROP CONSTRAINT IF EXISTS commitments_pkey;
ALTER TABLE IF EXISTS ONLY public.charges_taxes DROP CONSTRAINT IF EXISTS charges_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.charges DROP CONSTRAINT IF EXISTS charges_pkey;
ALTER TABLE IF EXISTS ONLY public.charge_filters DROP CONSTRAINT IF EXISTS charge_filters_pkey;
ALTER TABLE IF EXISTS ONLY public.charge_filter_values DROP CONSTRAINT IF EXISTS charge_filter_values_pkey;
ALTER TABLE IF EXISTS ONLY public.cached_aggregations DROP CONSTRAINT IF EXISTS cached_aggregations_pkey;
ALTER TABLE IF EXISTS ONLY public.billable_metrics DROP CONSTRAINT IF EXISTS billable_metrics_pkey;
ALTER TABLE IF EXISTS ONLY public.billable_metric_filters DROP CONSTRAINT IF EXISTS billable_metric_filters_pkey;
ALTER TABLE IF EXISTS ONLY public.ar_internal_metadata DROP CONSTRAINT IF EXISTS ar_internal_metadata_pkey;
ALTER TABLE IF EXISTS ONLY public.applied_usage_thresholds DROP CONSTRAINT IF EXISTS applied_usage_thresholds_pkey;
ALTER TABLE IF EXISTS ONLY public.applied_invoice_custom_sections DROP CONSTRAINT IF EXISTS applied_invoice_custom_sections_pkey;
ALTER TABLE IF EXISTS ONLY public.applied_coupons DROP CONSTRAINT IF EXISTS applied_coupons_pkey;
ALTER TABLE IF EXISTS ONLY public.applied_add_ons DROP CONSTRAINT IF EXISTS applied_add_ons_pkey;
ALTER TABLE IF EXISTS ONLY public.api_keys DROP CONSTRAINT IF EXISTS api_keys_pkey;
ALTER TABLE IF EXISTS ONLY public.adjusted_fees DROP CONSTRAINT IF EXISTS adjusted_fees_pkey;
ALTER TABLE IF EXISTS ONLY public.add_ons_taxes DROP CONSTRAINT IF EXISTS add_ons_taxes_pkey;
ALTER TABLE IF EXISTS ONLY public.add_ons DROP CONSTRAINT IF EXISTS add_ons_pkey;
ALTER TABLE IF EXISTS ONLY public.active_storage_variant_records DROP CONSTRAINT IF EXISTS active_storage_variant_records_pkey;
ALTER TABLE IF EXISTS ONLY public.active_storage_blobs DROP CONSTRAINT IF EXISTS active_storage_blobs_pkey;
ALTER TABLE IF EXISTS ONLY public.active_storage_attachments DROP CONSTRAINT IF EXISTS active_storage_attachments_pkey;
ALTER TABLE IF EXISTS public.versions ALTER COLUMN id DROP DEFAULT;
DROP TABLE IF EXISTS public.webhooks;
DROP TABLE IF EXISTS public.webhook_endpoints;
DROP TABLE IF EXISTS public.wallets;
DROP TABLE IF EXISTS public.wallet_transactions;
DROP SEQUENCE IF EXISTS public.versions_id_seq;
DROP TABLE IF EXISTS public.versions;
DROP TABLE IF EXISTS public.users;
DROP TABLE IF EXISTS public.usage_thresholds;
DROP TABLE IF EXISTS public.taxes;
DROP TABLE IF EXISTS public.subscriptions;
DROP TABLE IF EXISTS public.subscription_event_triggers;
DROP TABLE IF EXISTS public.schema_migrations;
DROP TABLE IF EXISTS public.refunds;
DROP TABLE IF EXISTS public.recurring_transaction_rules;
DROP TABLE IF EXISTS public.quantified_events;
DROP TABLE IF EXISTS public.plans_taxes;
DROP TABLE IF EXISTS public.plans;
DROP TABLE IF EXISTS public.payments;
DROP TABLE IF EXISTS public.payment_requests;
DROP TABLE IF EXISTS public.payment_providers;
DROP TABLE IF EXISTS public.payment_provider_customers;
DROP TABLE IF EXISTS public.password_resets;
DROP TABLE IF EXISTS public.organizations;
DROP TABLE IF EXISTS public.memberships;
DROP TABLE IF EXISTS public.lifetime_usages;
DROP MATERIALIZED VIEW IF EXISTS public.last_hour_events_mv;
DROP TABLE IF EXISTS public.invoices_taxes;
DROP TABLE IF EXISTS public.invoices_payment_requests;
DROP TABLE IF EXISTS public.invoices;
DROP TABLE IF EXISTS public.invoice_subscriptions;
DROP TABLE IF EXISTS public.invoice_metadata;
DROP TABLE IF EXISTS public.invoice_errors;
DROP TABLE IF EXISTS public.invoice_custom_sections;
DROP TABLE IF EXISTS public.invoice_custom_section_selections;
DROP TABLE IF EXISTS public.invites;
DROP TABLE IF EXISTS public.integrations;
DROP TABLE IF EXISTS public.integration_resources;
DROP TABLE IF EXISTS public.integration_mappings;
DROP TABLE IF EXISTS public.integration_items;
DROP TABLE IF EXISTS public.integration_customers;
DROP TABLE IF EXISTS public.integration_collection_mappings;
DROP TABLE IF EXISTS public.groups;
DROP TABLE IF EXISTS public.group_properties;
DROP TABLE IF EXISTS public.fees_taxes;
DROP TABLE IF EXISTS public.fees;
DROP TABLE IF EXISTS public.events;
DROP TABLE IF EXISTS public.error_details;
DROP TABLE IF EXISTS public.dunning_campaigns;
DROP TABLE IF EXISTS public.dunning_campaign_thresholds;
DROP TABLE IF EXISTS public.data_exports;
DROP TABLE IF EXISTS public.data_export_parts;
DROP TABLE IF EXISTS public.daily_usages;
DROP TABLE IF EXISTS public.customers_taxes;
DROP TABLE IF EXISTS public.customers;
DROP TABLE IF EXISTS public.customer_metadata;
DROP TABLE IF EXISTS public.credits;
DROP TABLE IF EXISTS public.credit_notes_taxes;
DROP TABLE IF EXISTS public.credit_notes;
DROP TABLE IF EXISTS public.credit_note_items;
DROP TABLE IF EXISTS public.coupons;
DROP TABLE IF EXISTS public.coupon_targets;
DROP TABLE IF EXISTS public.commitments_taxes;
DROP TABLE IF EXISTS public.commitments;
DROP TABLE IF EXISTS public.charges_taxes;
DROP TABLE IF EXISTS public.charges;
DROP TABLE IF EXISTS public.charge_filters;
DROP TABLE IF EXISTS public.charge_filter_values;
DROP TABLE IF EXISTS public.cached_aggregations;
DROP VIEW IF EXISTS public.billable_metrics_grouped_charges;
DROP TABLE IF EXISTS public.billable_metrics;
DROP TABLE IF EXISTS public.billable_metric_filters;
DROP TABLE IF EXISTS public.ar_internal_metadata;
DROP TABLE IF EXISTS public.applied_usage_thresholds;
DROP TABLE IF EXISTS public.applied_invoice_custom_sections;
DROP TABLE IF EXISTS public.applied_coupons;
DROP TABLE IF EXISTS public.applied_add_ons;
DROP TABLE IF EXISTS public.api_keys;
DROP TABLE IF EXISTS public.adjusted_fees;
DROP TABLE IF EXISTS public.add_ons_taxes;
DROP TABLE IF EXISTS public.add_ons;
DROP TABLE IF EXISTS public.active_storage_variant_records;
DROP TABLE IF EXISTS public.active_storage_blobs;
DROP TABLE IF EXISTS public.active_storage_attachments;
DROP PROCEDURE IF EXISTS public.trigger_subscription_update(IN p_organization_id uuid, IN p_external_subscription_id character varying, INOUT result_id uuid);
DROP TYPE IF EXISTS public.tax_status;
DROP TYPE IF EXISTS public.subscription_invoicing_reason;
DROP TYPE IF EXISTS public.payment_payable_payment_status;
DROP TYPE IF EXISTS public.customer_type;
DROP TYPE IF EXISTS public.billable_metric_weighted_interval;
DROP TYPE IF EXISTS public.billable_metric_rounding_function;
DROP EXTENSION IF EXISTS unaccent;
DROP EXTENSION IF EXISTS pgcrypto;
-- *not* dropping schema, since initdb creates it
--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: billable_metric_rounding_function; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.billable_metric_rounding_function AS ENUM (
    'round',
    'floor',
    'ceil'
);


--
-- Name: billable_metric_weighted_interval; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.billable_metric_weighted_interval AS ENUM (
    'seconds'
);


--
-- Name: customer_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.customer_type AS ENUM (
    'company',
    'individual'
);


--
-- Name: payment_payable_payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_payable_payment_status AS ENUM (
    'pending',
    'processing',
    'succeeded',
    'failed'
);


--
-- Name: subscription_invoicing_reason; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.subscription_invoicing_reason AS ENUM (
    'subscription_starting',
    'subscription_periodic',
    'subscription_terminating',
    'in_advance_charge',
    'in_advance_charge_periodic',
    'progressive_billing'
);


--
-- Name: tax_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.tax_status AS ENUM (
    'pending',
    'succeeded',
    'failed'
);


--
-- Name: trigger_subscription_update(uuid, character varying, uuid); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.trigger_subscription_update(IN p_organization_id uuid, IN p_external_subscription_id character varying, INOUT result_id uuid)
    LANGUAGE plpgsql
    AS $$
  BEGIN
      INSERT INTO subscription_event_triggers (
          organization_id,
          external_subscription_id,
          created_at
      )
      VALUES (
          p_organization_id,
          p_external_subscription_id,
          NOW()
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO result_id;
  END;
  $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    record_id uuid
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: add_ons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.add_ons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    description character varying,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    invoice_display_name character varying
);


--
-- Name: add_ons_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.add_ons_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    add_on_id uuid NOT NULL,
    tax_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: adjusted_fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.adjusted_fees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fee_id uuid,
    invoice_id uuid NOT NULL,
    subscription_id uuid,
    charge_id uuid,
    invoice_display_name character varying,
    fee_type integer,
    adjusted_units boolean DEFAULT false NOT NULL,
    adjusted_amount boolean DEFAULT false NOT NULL,
    units numeric DEFAULT 0.0 NOT NULL,
    unit_amount_cents bigint DEFAULT 0 NOT NULL,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    group_id uuid,
    grouped_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    charge_filter_id uuid,
    unit_precise_amount_cents numeric(40,15) DEFAULT 0.0 NOT NULL
);


--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    name character varying,
    permissions jsonb NOT NULL
);


--
-- Name: applied_add_ons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applied_add_ons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    add_on_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: applied_coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applied_coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coupon_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    amount_cents bigint,
    amount_currency character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    terminated_at timestamp without time zone,
    percentage_rate numeric(10,5),
    frequency integer DEFAULT 0 NOT NULL,
    frequency_duration integer,
    frequency_duration_remaining integer
);


--
-- Name: applied_invoice_custom_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applied_invoice_custom_sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    display_name character varying,
    details character varying,
    invoice_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: applied_usage_thresholds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applied_usage_thresholds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    usage_threshold_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    lifetime_usage_amount_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: billable_metric_filters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billable_metric_filters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    billable_metric_id uuid NOT NULL,
    key character varying NOT NULL,
    "values" character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone
);


--
-- Name: billable_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billable_metrics (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    description character varying,
    properties jsonb DEFAULT '{}'::jsonb,
    aggregation_type integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    field_name character varying,
    deleted_at timestamp(6) without time zone,
    recurring boolean DEFAULT false NOT NULL,
    weighted_interval public.billable_metric_weighted_interval,
    custom_aggregator text,
    expression character varying,
    rounding_function public.billable_metric_rounding_function,
    rounding_precision integer
);


--
-- Name: billable_metrics_grouped_charges; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.billable_metrics_grouped_charges AS
SELECT
    NULL::uuid AS organization_id,
    NULL::character varying AS code,
    NULL::integer AS aggregation_type,
    NULL::character varying AS field_name,
    NULL::uuid AS plan_id,
    NULL::uuid AS charge_id,
    NULL::boolean AS pay_in_advance,
    NULL::jsonb AS grouped_by,
    NULL::uuid AS charge_filter_id,
    NULL::json AS filters,
    NULL::jsonb AS filters_grouped_by;


--
-- Name: cached_aggregations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cached_aggregations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    event_id uuid,
    "timestamp" timestamp(6) without time zone NOT NULL,
    external_subscription_id character varying NOT NULL,
    charge_id uuid NOT NULL,
    group_id uuid,
    current_aggregation numeric,
    max_aggregation numeric,
    max_aggregation_with_proration numeric,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    grouped_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    charge_filter_id uuid,
    current_amount numeric,
    event_transaction_id character varying
);


--
-- Name: charge_filter_values; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.charge_filter_values (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    charge_filter_id uuid NOT NULL,
    billable_metric_filter_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    "values" character varying[] DEFAULT '{}'::character varying[] NOT NULL
);


--
-- Name: charge_filters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.charge_filters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    charge_id uuid NOT NULL,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    invoice_display_name character varying
);


--
-- Name: charges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.charges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    billable_metric_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    plan_id uuid,
    amount_currency character varying,
    charge_model integer DEFAULT 0 NOT NULL,
    properties jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    deleted_at timestamp(6) without time zone,
    pay_in_advance boolean DEFAULT false NOT NULL,
    min_amount_cents bigint DEFAULT 0 NOT NULL,
    invoiceable boolean DEFAULT true NOT NULL,
    prorated boolean DEFAULT false NOT NULL,
    invoice_display_name character varying,
    regroup_paid_fees integer,
    parent_id uuid
);


--
-- Name: charges_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.charges_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    charge_id uuid NOT NULL,
    tax_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: commitments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commitments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    commitment_type integer NOT NULL,
    amount_cents bigint NOT NULL,
    invoice_display_name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: commitments_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.commitments_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    commitment_id uuid NOT NULL,
    tax_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: coupon_targets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupon_targets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coupon_id uuid NOT NULL,
    plan_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    billable_metric_id uuid
);


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying,
    status integer DEFAULT 0 NOT NULL,
    terminated_at timestamp(6) without time zone,
    amount_cents bigint,
    amount_currency character varying,
    expiration integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    coupon_type integer DEFAULT 0 NOT NULL,
    percentage_rate numeric(10,5),
    frequency integer DEFAULT 0 NOT NULL,
    frequency_duration integer,
    expiration_at timestamp(6) without time zone,
    reusable boolean DEFAULT true NOT NULL,
    limited_plans boolean DEFAULT false NOT NULL,
    deleted_at timestamp(6) without time zone,
    limited_billable_metrics boolean DEFAULT false NOT NULL,
    description text
);


--
-- Name: credit_note_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_note_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    credit_note_id uuid NOT NULL,
    fee_id uuid,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    precise_amount_cents numeric(30,5) NOT NULL
);


--
-- Name: credit_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    invoice_id uuid NOT NULL,
    sequential_id integer NOT NULL,
    number character varying NOT NULL,
    credit_amount_cents bigint DEFAULT 0 NOT NULL,
    credit_amount_currency character varying NOT NULL,
    credit_status integer,
    balance_amount_cents bigint DEFAULT 0 NOT NULL,
    balance_amount_currency character varying DEFAULT '0'::character varying NOT NULL,
    reason integer NOT NULL,
    file character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    total_amount_cents bigint DEFAULT 0 NOT NULL,
    total_amount_currency character varying NOT NULL,
    refund_amount_cents bigint DEFAULT 0 NOT NULL,
    refund_amount_currency character varying,
    refund_status integer,
    voided_at timestamp(6) without time zone,
    description text,
    taxes_amount_cents bigint DEFAULT 0 NOT NULL,
    refunded_at timestamp(6) without time zone,
    issuing_date date NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    coupons_adjustment_amount_cents bigint DEFAULT 0 NOT NULL,
    precise_coupons_adjustment_amount_cents numeric(30,5) DEFAULT 0.0 NOT NULL,
    precise_taxes_amount_cents numeric(30,5) DEFAULT 0.0 NOT NULL,
    taxes_rate double precision DEFAULT 0.0 NOT NULL
);


--
-- Name: credit_notes_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_notes_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    credit_note_id uuid NOT NULL,
    tax_id uuid,
    tax_description character varying,
    tax_code character varying NOT NULL,
    tax_name character varying NOT NULL,
    tax_rate double precision DEFAULT 0.0 NOT NULL,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    base_amount_cents bigint DEFAULT 0 NOT NULL
);


--
-- Name: credits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid,
    applied_coupon_id uuid,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    credit_note_id uuid,
    before_taxes boolean DEFAULT false NOT NULL,
    progressive_billing_invoice_id uuid
);


--
-- Name: customer_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_metadata (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    key character varying NOT NULL,
    value character varying NOT NULL,
    display_in_invoice boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    external_id character varying NOT NULL,
    name character varying,
    organization_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    country character varying,
    address_line1 character varying,
    address_line2 character varying,
    state character varying,
    zipcode character varying,
    email character varying,
    city character varying,
    url character varying,
    phone character varying,
    logo_url character varying,
    legal_name character varying,
    legal_number character varying,
    vat_rate double precision,
    payment_provider character varying,
    slug character varying,
    sequential_id bigint,
    currency character varying,
    invoice_grace_period integer,
    timezone character varying,
    deleted_at timestamp(6) without time zone,
    document_locale character varying,
    tax_identification_number character varying,
    net_payment_term integer,
    external_salesforce_id character varying,
    payment_provider_code character varying,
    shipping_address_line1 character varying,
    shipping_address_line2 character varying,
    shipping_city character varying,
    shipping_zipcode character varying,
    shipping_state character varying,
    shipping_country character varying,
    finalize_zero_amount_invoice integer DEFAULT 0 NOT NULL,
    firstname character varying,
    lastname character varying,
    customer_type public.customer_type,
    applied_dunning_campaign_id uuid,
    exclude_from_dunning_campaign boolean DEFAULT false NOT NULL,
    last_dunning_campaign_attempt integer DEFAULT 0 NOT NULL,
    last_dunning_campaign_attempt_at timestamp without time zone,
    skip_invoice_custom_sections boolean DEFAULT false NOT NULL,
    CONSTRAINT check_customers_on_invoice_grace_period CHECK ((invoice_grace_period >= 0)),
    CONSTRAINT check_customers_on_net_payment_term CHECK ((net_payment_term >= 0))
);


--
-- Name: customers_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    tax_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: daily_usages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_usages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    subscription_id uuid NOT NULL,
    external_subscription_id character varying NOT NULL,
    from_datetime timestamp(6) without time zone NOT NULL,
    to_datetime timestamp(6) without time zone NOT NULL,
    usage jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    refreshed_at timestamp(6) without time zone NOT NULL,
    usage_diff jsonb DEFAULT '"{}"'::jsonb NOT NULL
);


--
-- Name: data_export_parts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_export_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    index integer,
    data_export_id uuid NOT NULL,
    object_ids uuid[] NOT NULL,
    completed boolean DEFAULT false NOT NULL,
    csv_lines text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: data_exports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_exports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    format integer,
    resource_type character varying NOT NULL,
    resource_query jsonb DEFAULT '{}'::jsonb,
    status integer DEFAULT 0 NOT NULL,
    expires_at timestamp without time zone,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    membership_id uuid,
    organization_id uuid
);


--
-- Name: dunning_campaign_thresholds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dunning_campaign_thresholds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dunning_campaign_id uuid NOT NULL,
    currency character varying NOT NULL,
    amount_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp without time zone
);


--
-- Name: dunning_campaigns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dunning_campaigns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    description text,
    applied_to_organization boolean DEFAULT false NOT NULL,
    days_between_attempts integer DEFAULT 1 NOT NULL,
    max_attempts integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp without time zone
);


--
-- Name: error_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.error_details (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_type character varying NOT NULL,
    owner_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    deleted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    error_code integer DEFAULT 0 NOT NULL
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    customer_id uuid,
    transaction_id character varying NOT NULL,
    code character varying NOT NULL,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    "timestamp" timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    subscription_id uuid,
    deleted_at timestamp(6) without time zone,
    external_customer_id character varying,
    external_subscription_id character varying,
    precise_total_amount_cents numeric(40,15)
);


--
-- Name: fees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid,
    charge_id uuid,
    subscription_id uuid,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    taxes_amount_cents bigint NOT NULL,
    taxes_rate double precision DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    units numeric DEFAULT 0.0 NOT NULL,
    applied_add_on_id uuid,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    fee_type integer,
    invoiceable_type character varying,
    invoiceable_id uuid,
    events_count integer,
    group_id uuid,
    pay_in_advance_event_id uuid,
    payment_status integer DEFAULT 0 NOT NULL,
    succeeded_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    refunded_at timestamp(6) without time zone,
    true_up_parent_fee_id uuid,
    add_on_id uuid,
    description character varying,
    unit_amount_cents bigint DEFAULT 0 NOT NULL,
    pay_in_advance boolean DEFAULT false NOT NULL,
    precise_coupons_amount_cents numeric(30,5) DEFAULT 0.0 NOT NULL,
    total_aggregated_units numeric,
    invoice_display_name character varying,
    precise_unit_amount numeric(30,15) DEFAULT 0.0 NOT NULL,
    amount_details jsonb DEFAULT '{}'::jsonb NOT NULL,
    charge_filter_id uuid,
    grouped_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    pay_in_advance_event_transaction_id character varying,
    deleted_at timestamp(6) without time zone,
    precise_amount_cents numeric(40,15) DEFAULT 0.0 NOT NULL,
    taxes_precise_amount_cents numeric(40,15) DEFAULT 0.0 NOT NULL,
    taxes_base_rate double precision DEFAULT 1.0 NOT NULL,
    organization_id uuid
);


--
-- Name: fees_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fees_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fee_id uuid NOT NULL,
    tax_id uuid,
    tax_description character varying,
    tax_code character varying NOT NULL,
    tax_name character varying NOT NULL,
    tax_rate double precision DEFAULT 0.0 NOT NULL,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    precise_amount_cents numeric(40,15) DEFAULT 0.0 NOT NULL
);


--
-- Name: group_properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.group_properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    charge_id uuid NOT NULL,
    group_id uuid NOT NULL,
    "values" jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    invoice_display_name character varying
);


--
-- Name: groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    billable_metric_id uuid NOT NULL,
    parent_group_id uuid,
    key character varying NOT NULL,
    value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone
);


--
-- Name: integration_collection_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_collection_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    mapping_type integer NOT NULL,
    type character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: integration_customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    external_customer_id character varying,
    type character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: integration_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    item_type integer NOT NULL,
    external_id character varying NOT NULL,
    external_account_code character varying,
    external_name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: integration_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    mappable_type character varying NOT NULL,
    mappable_id uuid NOT NULL,
    type character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: integration_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integration_resources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    syncable_type character varying NOT NULL,
    syncable_id uuid NOT NULL,
    external_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    integration_id uuid,
    resource_type integer DEFAULT 0 NOT NULL
);


--
-- Name: integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    type character varying NOT NULL,
    secrets character varying,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    membership_id uuid,
    email character varying NOT NULL,
    token character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    accepted_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    role integer DEFAULT 0 NOT NULL
);


--
-- Name: invoice_custom_section_selections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_custom_section_selections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_custom_section_id uuid NOT NULL,
    organization_id uuid,
    customer_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoice_custom_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_custom_sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    code character varying NOT NULL,
    description character varying,
    display_name character varying,
    details character varying,
    organization_id uuid NOT NULL,
    deleted_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoice_errors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_errors (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    backtrace text,
    invoice json,
    subscriptions json,
    error json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoice_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_metadata (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    key character varying NOT NULL,
    value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoice_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoice_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    subscription_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    recurring boolean,
    "timestamp" timestamp(6) without time zone,
    from_datetime timestamp(6) without time zone,
    to_datetime timestamp(6) without time zone,
    charges_from_datetime timestamp(6) without time zone,
    charges_to_datetime timestamp(6) without time zone,
    invoicing_reason public.subscription_invoicing_reason
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    issuing_date date,
    taxes_amount_cents bigint DEFAULT 0 NOT NULL,
    total_amount_cents bigint DEFAULT 0 NOT NULL,
    invoice_type integer DEFAULT 0 NOT NULL,
    payment_status integer DEFAULT 0 NOT NULL,
    number character varying DEFAULT ''::character varying NOT NULL,
    sequential_id integer,
    file character varying,
    customer_id uuid,
    taxes_rate double precision DEFAULT 0.0 NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    payment_attempts integer DEFAULT 0 NOT NULL,
    ready_for_payment_processing boolean DEFAULT true NOT NULL,
    organization_id uuid NOT NULL,
    version_number integer DEFAULT 4 NOT NULL,
    currency character varying,
    fees_amount_cents bigint DEFAULT 0 NOT NULL,
    coupons_amount_cents bigint DEFAULT 0 NOT NULL,
    credit_notes_amount_cents bigint DEFAULT 0 NOT NULL,
    prepaid_credit_amount_cents bigint DEFAULT 0 NOT NULL,
    sub_total_excluding_taxes_amount_cents bigint DEFAULT 0 NOT NULL,
    sub_total_including_taxes_amount_cents bigint DEFAULT 0 NOT NULL,
    payment_due_date date,
    net_payment_term integer DEFAULT 0 NOT NULL,
    voided_at timestamp(6) without time zone,
    organization_sequential_id integer DEFAULT 0 NOT NULL,
    ready_to_be_refreshed boolean DEFAULT false NOT NULL,
    payment_dispute_lost_at timestamp(6) without time zone,
    skip_charges boolean DEFAULT false NOT NULL,
    payment_overdue boolean DEFAULT false,
    negative_amount_cents bigint DEFAULT 0 NOT NULL,
    progressive_billing_credit_amount_cents bigint DEFAULT 0 NOT NULL,
    tax_status public.tax_status,
    CONSTRAINT check_organizations_on_net_payment_term CHECK ((net_payment_term >= 0))
);


--
-- Name: invoices_payment_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices_payment_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    payment_request_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: invoices_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid NOT NULL,
    tax_id uuid,
    tax_description character varying,
    tax_code character varying NOT NULL,
    tax_name character varying NOT NULL,
    tax_rate double precision DEFAULT 0.0 NOT NULL,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    fees_amount_cents bigint DEFAULT 0 NOT NULL,
    taxable_base_amount_cents bigint DEFAULT 0 NOT NULL
);


--
-- Name: last_hour_events_mv; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.last_hour_events_mv AS
 WITH billable_metric_filters AS (
         SELECT billable_metrics_1.organization_id AS bm_organization_id,
            billable_metrics_1.id AS bm_id,
            billable_metrics_1.code AS bm_code,
            filters.key AS filter_key,
            filters."values" AS filter_values
           FROM (public.billable_metrics billable_metrics_1
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
    ((events.properties ->> (billable_metrics.field_name)::text) ~ '^-?\d+(\.\d+)?$'::text) AS is_numeric_field_value,
    (events.properties ? (billable_metric_filters.filter_key)::text) AS has_filter_keys,
    ((events.properties ->> (billable_metric_filters.filter_key)::text) = ANY ((billable_metric_filters.filter_values)::text[])) AS has_valid_filter_values
   FROM ((public.events
     LEFT JOIN public.billable_metrics ON ((((billable_metrics.code)::text = (events.code)::text) AND (events.organization_id = billable_metrics.organization_id))))
     LEFT JOIN billable_metric_filters ON ((billable_metrics.id = billable_metric_filters.bm_id)))
  WHERE ((events.deleted_at IS NULL) AND (events.created_at >= (date_trunc('hour'::text, now()) - '01:00:00'::interval)) AND (events.created_at < date_trunc('hour'::text, now())) AND (billable_metrics.deleted_at IS NULL))
  WITH NO DATA;


--
-- Name: lifetime_usages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lifetime_usages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    subscription_id uuid NOT NULL,
    current_usage_amount_cents bigint DEFAULT 0 NOT NULL,
    invoiced_usage_amount_cents bigint DEFAULT 0 NOT NULL,
    recalculate_current_usage boolean DEFAULT false NOT NULL,
    recalculate_invoiced_usage boolean DEFAULT false NOT NULL,
    current_usage_amount_refreshed_at timestamp without time zone,
    invoiced_usage_amount_refreshed_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    historical_usage_amount_cents bigint DEFAULT 0 NOT NULL
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    revoked_at timestamp(6) without time zone
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    api_key character varying,
    webhook_url character varying,
    vat_rate double precision DEFAULT 0.0 NOT NULL,
    country character varying,
    address_line1 character varying,
    address_line2 character varying,
    state character varying,
    zipcode character varying,
    email character varying,
    city character varying,
    logo character varying,
    legal_name character varying,
    legal_number character varying,
    invoice_footer text,
    invoice_grace_period integer DEFAULT 0 NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    document_locale character varying DEFAULT 'en'::character varying NOT NULL,
    email_settings character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    tax_identification_number character varying,
    net_payment_term integer DEFAULT 0 NOT NULL,
    default_currency character varying DEFAULT 'USD'::character varying NOT NULL,
    document_numbering integer DEFAULT 0 NOT NULL,
    document_number_prefix character varying,
    eu_tax_management boolean DEFAULT false,
    clickhouse_aggregation boolean DEFAULT false NOT NULL,
    premium_integrations character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    custom_aggregation boolean DEFAULT false,
    finalize_zero_amount_invoice boolean DEFAULT true NOT NULL,
    clickhouse_events_store boolean DEFAULT false NOT NULL,
    hmac_key character varying NOT NULL,
    CONSTRAINT check_organizations_on_invoice_grace_period CHECK ((invoice_grace_period >= 0)),
    CONSTRAINT check_organizations_on_net_payment_term CHECK ((net_payment_term >= 0))
);


--
-- Name: password_resets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_resets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token character varying NOT NULL,
    expire_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: payment_provider_customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_provider_customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    payment_provider_id uuid,
    type character varying NOT NULL,
    provider_customer_id character varying,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone
);


--
-- Name: payment_providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    type character varying NOT NULL,
    secrets character varying,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    deleted_at timestamp(6) without time zone
);


--
-- Name: payment_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    email character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    organization_id uuid NOT NULL,
    payment_status integer DEFAULT 0 NOT NULL,
    payment_attempts integer DEFAULT 0 NOT NULL,
    ready_for_payment_processing boolean DEFAULT true NOT NULL,
    dunning_campaign_id uuid
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invoice_id uuid,
    payment_provider_id uuid,
    payment_provider_customer_id uuid,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    provider_payment_id character varying,
    status character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    payable_type character varying DEFAULT 'Invoice'::character varying NOT NULL,
    payable_id uuid,
    provider_payment_data jsonb DEFAULT '{}'::jsonb,
    payable_payment_status public.payment_payable_payment_status
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    code character varying NOT NULL,
    "interval" integer NOT NULL,
    description character varying,
    amount_cents bigint NOT NULL,
    amount_currency character varying NOT NULL,
    trial_period double precision,
    pay_in_advance boolean DEFAULT false NOT NULL,
    bill_charges_monthly boolean,
    parent_id uuid,
    deleted_at timestamp(6) without time zone,
    pending_deletion boolean DEFAULT false NOT NULL,
    invoice_display_name character varying
);


--
-- Name: plans_taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans_taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    tax_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: quantified_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quantified_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    external_subscription_id character varying NOT NULL,
    external_id character varying,
    added_at timestamp(6) without time zone NOT NULL,
    removed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    billable_metric_id uuid,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    deleted_at timestamp(6) without time zone,
    group_id uuid,
    organization_id uuid NOT NULL,
    grouped_by jsonb DEFAULT '{}'::jsonb NOT NULL,
    charge_filter_id uuid
);


--
-- Name: recurring_transaction_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recurring_transaction_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    wallet_id uuid NOT NULL,
    trigger integer DEFAULT 0 NOT NULL,
    paid_credits numeric(30,5) DEFAULT 0.0 NOT NULL,
    granted_credits numeric(30,5) DEFAULT 0.0 NOT NULL,
    threshold_credits numeric(30,5) DEFAULT 0.0,
    "interval" integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    method integer DEFAULT 0 NOT NULL,
    target_ongoing_balance numeric(30,5),
    started_at timestamp(6) without time zone,
    invoice_requires_successful_payment boolean DEFAULT false NOT NULL,
    transaction_metadata jsonb DEFAULT '[]'::jsonb
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    credit_note_id uuid NOT NULL,
    payment_provider_id uuid,
    payment_provider_customer_id uuid NOT NULL,
    amount_cents bigint DEFAULT 0 NOT NULL,
    amount_currency character varying NOT NULL,
    status character varying NOT NULL,
    provider_refund_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: subscription_event_triggers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_event_triggers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    external_subscription_id character varying NOT NULL,
    start_processing_at timestamp without time zone,
    created_at timestamp without time zone NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    plan_id uuid NOT NULL,
    status integer NOT NULL,
    canceled_at timestamp without time zone,
    terminated_at timestamp without time zone,
    started_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    previous_subscription_id uuid,
    name character varying,
    external_id character varying NOT NULL,
    billing_time integer DEFAULT 0 NOT NULL,
    subscription_at timestamp(6) without time zone,
    ending_at timestamp(6) without time zone,
    trial_ended_at timestamp(6) without time zone
);


--
-- Name: taxes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    description character varying,
    code character varying NOT NULL,
    name character varying NOT NULL,
    rate double precision DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    applied_to_organization boolean DEFAULT false NOT NULL,
    auto_generated boolean DEFAULT false NOT NULL
);


--
-- Name: usage_thresholds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_thresholds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    threshold_display_name character varying,
    amount_cents bigint NOT NULL,
    recurring boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying,
    password_digest character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    item_type character varying NOT NULL,
    item_id character varying NOT NULL,
    event character varying NOT NULL,
    whodunnit character varying,
    object jsonb,
    object_changes jsonb,
    created_at timestamp(6) without time zone,
    lago_version character varying
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    wallet_id uuid NOT NULL,
    transaction_type integer NOT NULL,
    status integer NOT NULL,
    amount numeric(30,5) DEFAULT 0.0 NOT NULL,
    credit_amount numeric(30,5) DEFAULT 0.0 NOT NULL,
    settled_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    invoice_id uuid,
    source integer DEFAULT 0 NOT NULL,
    transaction_status integer DEFAULT 0 NOT NULL,
    invoice_requires_successful_payment boolean DEFAULT false NOT NULL,
    metadata jsonb DEFAULT '[]'::jsonb,
    credit_note_id uuid
);


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    status integer NOT NULL,
    name character varying,
    rate_amount numeric(30,5) DEFAULT 0.0 NOT NULL,
    credits_balance numeric(30,5) DEFAULT 0.0 NOT NULL,
    consumed_credits numeric(30,5) DEFAULT 0.0 NOT NULL,
    expiration_at timestamp without time zone,
    last_balance_sync_at timestamp without time zone,
    last_consumed_credit_at timestamp without time zone,
    terminated_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    balance_cents bigint DEFAULT 0 NOT NULL,
    balance_currency character varying NOT NULL,
    consumed_amount_cents bigint DEFAULT 0 NOT NULL,
    consumed_amount_currency character varying NOT NULL,
    ongoing_balance_cents bigint DEFAULT 0 NOT NULL,
    ongoing_usage_balance_cents bigint DEFAULT 0 NOT NULL,
    credits_ongoing_balance numeric(30,5) DEFAULT 0.0 NOT NULL,
    credits_ongoing_usage_balance numeric(30,5) DEFAULT 0.0 NOT NULL,
    depleted_ongoing_balance boolean DEFAULT false NOT NULL,
    invoice_requires_successful_payment boolean DEFAULT false NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    ready_to_be_refreshed boolean DEFAULT false NOT NULL
);


--
-- Name: webhook_endpoints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhook_endpoints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    webhook_url character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    signature_algo integer DEFAULT 0 NOT NULL
);


--
-- Name: webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhooks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    object_id uuid,
    object_type character varying,
    status integer DEFAULT 0 NOT NULL,
    retries integer DEFAULT 0 NOT NULL,
    http_status integer,
    endpoint character varying,
    webhook_type character varying,
    payload json,
    response json,
    last_retried_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    webhook_endpoint_id uuid
);


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: add_ons add_ons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.add_ons
    ADD CONSTRAINT add_ons_pkey PRIMARY KEY (id);


--
-- Name: add_ons_taxes add_ons_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.add_ons_taxes
    ADD CONSTRAINT add_ons_taxes_pkey PRIMARY KEY (id);


--
-- Name: adjusted_fees adjusted_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT adjusted_fees_pkey PRIMARY KEY (id);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: applied_add_ons applied_add_ons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_add_ons
    ADD CONSTRAINT applied_add_ons_pkey PRIMARY KEY (id);


--
-- Name: applied_coupons applied_coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_coupons
    ADD CONSTRAINT applied_coupons_pkey PRIMARY KEY (id);


--
-- Name: applied_invoice_custom_sections applied_invoice_custom_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_invoice_custom_sections
    ADD CONSTRAINT applied_invoice_custom_sections_pkey PRIMARY KEY (id);


--
-- Name: applied_usage_thresholds applied_usage_thresholds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_usage_thresholds
    ADD CONSTRAINT applied_usage_thresholds_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: billable_metric_filters billable_metric_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billable_metric_filters
    ADD CONSTRAINT billable_metric_filters_pkey PRIMARY KEY (id);


--
-- Name: billable_metrics billable_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billable_metrics
    ADD CONSTRAINT billable_metrics_pkey PRIMARY KEY (id);


--
-- Name: cached_aggregations cached_aggregations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cached_aggregations
    ADD CONSTRAINT cached_aggregations_pkey PRIMARY KEY (id);


--
-- Name: charge_filter_values charge_filter_values_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_filter_values
    ADD CONSTRAINT charge_filter_values_pkey PRIMARY KEY (id);


--
-- Name: charge_filters charge_filters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_filters
    ADD CONSTRAINT charge_filters_pkey PRIMARY KEY (id);


--
-- Name: charges charges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT charges_pkey PRIMARY KEY (id);


--
-- Name: charges_taxes charges_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges_taxes
    ADD CONSTRAINT charges_taxes_pkey PRIMARY KEY (id);


--
-- Name: commitments commitments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments
    ADD CONSTRAINT commitments_pkey PRIMARY KEY (id);


--
-- Name: commitments_taxes commitments_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments_taxes
    ADD CONSTRAINT commitments_taxes_pkey PRIMARY KEY (id);


--
-- Name: coupon_targets coupon_targets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_targets
    ADD CONSTRAINT coupon_targets_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: credit_note_items credit_note_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT credit_note_items_pkey PRIMARY KEY (id);


--
-- Name: credit_notes credit_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT credit_notes_pkey PRIMARY KEY (id);


--
-- Name: credit_notes_taxes credit_notes_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes_taxes
    ADD CONSTRAINT credit_notes_taxes_pkey PRIMARY KEY (id);


--
-- Name: credits credits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credits
    ADD CONSTRAINT credits_pkey PRIMARY KEY (id);


--
-- Name: customer_metadata customer_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_metadata
    ADD CONSTRAINT customer_metadata_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: customers_taxes customers_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_taxes
    ADD CONSTRAINT customers_taxes_pkey PRIMARY KEY (id);


--
-- Name: daily_usages daily_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usages
    ADD CONSTRAINT daily_usages_pkey PRIMARY KEY (id);


--
-- Name: data_export_parts data_export_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_export_parts
    ADD CONSTRAINT data_export_parts_pkey PRIMARY KEY (id);


--
-- Name: data_exports data_exports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_exports
    ADD CONSTRAINT data_exports_pkey PRIMARY KEY (id);


--
-- Name: dunning_campaign_thresholds dunning_campaign_thresholds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_campaign_thresholds
    ADD CONSTRAINT dunning_campaign_thresholds_pkey PRIMARY KEY (id);


--
-- Name: dunning_campaigns dunning_campaigns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_campaigns
    ADD CONSTRAINT dunning_campaigns_pkey PRIMARY KEY (id);


--
-- Name: error_details error_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_details
    ADD CONSTRAINT error_details_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: fees fees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fees_pkey PRIMARY KEY (id);


--
-- Name: fees_taxes fees_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees_taxes
    ADD CONSTRAINT fees_taxes_pkey PRIMARY KEY (id);


--
-- Name: group_properties group_properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_properties
    ADD CONSTRAINT group_properties_pkey PRIMARY KEY (id);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: integration_collection_mappings integration_collection_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_collection_mappings
    ADD CONSTRAINT integration_collection_mappings_pkey PRIMARY KEY (id);


--
-- Name: integration_customers integration_customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_customers
    ADD CONSTRAINT integration_customers_pkey PRIMARY KEY (id);


--
-- Name: integration_items integration_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_items
    ADD CONSTRAINT integration_items_pkey PRIMARY KEY (id);


--
-- Name: integration_mappings integration_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_mappings
    ADD CONSTRAINT integration_mappings_pkey PRIMARY KEY (id);


--
-- Name: integration_resources integration_resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_resources
    ADD CONSTRAINT integration_resources_pkey PRIMARY KEY (id);


--
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);


--
-- Name: invites invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_pkey PRIMARY KEY (id);


--
-- Name: invoice_custom_section_selections invoice_custom_section_selections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_section_selections
    ADD CONSTRAINT invoice_custom_section_selections_pkey PRIMARY KEY (id);


--
-- Name: invoice_custom_sections invoice_custom_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_sections
    ADD CONSTRAINT invoice_custom_sections_pkey PRIMARY KEY (id);


--
-- Name: invoice_errors invoice_errors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_errors
    ADD CONSTRAINT invoice_errors_pkey PRIMARY KEY (id);


--
-- Name: invoice_metadata invoice_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_metadata
    ADD CONSTRAINT invoice_metadata_pkey PRIMARY KEY (id);


--
-- Name: invoice_subscriptions invoice_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_subscriptions
    ADD CONSTRAINT invoice_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: invoices_payment_requests invoices_payment_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_payment_requests
    ADD CONSTRAINT invoices_payment_requests_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: invoices_taxes invoices_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_taxes
    ADD CONSTRAINT invoices_taxes_pkey PRIMARY KEY (id);


--
-- Name: lifetime_usages lifetime_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifetime_usages
    ADD CONSTRAINT lifetime_usages_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: password_resets password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- Name: payment_provider_customers payment_provider_customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_customers
    ADD CONSTRAINT payment_provider_customers_pkey PRIMARY KEY (id);


--
-- Name: payment_providers payment_providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_providers
    ADD CONSTRAINT payment_providers_pkey PRIMARY KEY (id);


--
-- Name: payment_requests payment_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_requests
    ADD CONSTRAINT payment_requests_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: plans_taxes plans_taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans_taxes
    ADD CONSTRAINT plans_taxes_pkey PRIMARY KEY (id);


--
-- Name: quantified_events quantified_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quantified_events
    ADD CONSTRAINT quantified_events_pkey PRIMARY KEY (id);


--
-- Name: recurring_transaction_rules recurring_transaction_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_transaction_rules
    ADD CONSTRAINT recurring_transaction_rules_pkey PRIMARY KEY (id);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: subscription_event_triggers subscription_event_triggers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_event_triggers
    ADD CONSTRAINT subscription_event_triggers_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: taxes taxes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT taxes_pkey PRIMARY KEY (id);


--
-- Name: usage_thresholds usage_thresholds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_thresholds
    ADD CONSTRAINT usage_thresholds_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: webhook_endpoints webhook_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT webhook_endpoints_pkey PRIMARY KEY (id);


--
-- Name: webhooks webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT webhooks_pkey PRIMARY KEY (id);


--
-- Name: idx_on_amount_cents_plan_id_recurring_888044d66b; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_amount_cents_plan_id_recurring_888044d66b ON public.usage_thresholds USING btree (amount_cents, plan_id, recurring) WHERE (deleted_at IS NULL);


--
-- Name: idx_on_dunning_campaign_id_currency_fbf233b2ae; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_dunning_campaign_id_currency_fbf233b2ae ON public.dunning_campaign_thresholds USING btree (dunning_campaign_id, currency) WHERE (deleted_at IS NULL);


--
-- Name: idx_on_external_subscription_id_organization_id_40aa74e2eb; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_external_subscription_id_organization_id_40aa74e2eb ON public.subscription_event_triggers USING btree (external_subscription_id, organization_id) WHERE (start_processing_at IS NULL);


--
-- Name: idx_on_invoice_custom_section_id_7edbcef7b5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_invoice_custom_section_id_7edbcef7b5 ON public.invoice_custom_section_selections USING btree (invoice_custom_section_id);


--
-- Name: idx_on_invoice_id_payment_request_id_aa550779a4; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_invoice_id_payment_request_id_aa550779a4 ON public.invoices_payment_requests USING btree (invoice_id, payment_request_id);


--
-- Name: idx_on_organization_id_deleted_at_225e3f789d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_deleted_at_225e3f789d ON public.invoice_custom_sections USING btree (organization_id, deleted_at);


--
-- Name: idx_on_organization_id_external_subscription_id_df3a30d96d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_external_subscription_id_df3a30d96d ON public.daily_usages USING btree (organization_id, external_subscription_id);


--
-- Name: idx_on_start_processing_at_external_subscription_id_31b81116ce; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_start_processing_at_external_subscription_id_31b81116ce ON public.subscription_event_triggers USING btree (start_processing_at, external_subscription_id, organization_id);


--
-- Name: idx_on_usage_threshold_id_invoice_id_cb82cdf163; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_usage_threshold_id_invoice_id_cb82cdf163 ON public.applied_usage_thresholds USING btree (usage_threshold_id, invoice_id);


--
-- Name: index_active_charge_filter_values; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_charge_filter_values ON public.charge_filter_values USING btree (charge_filter_id) WHERE (deleted_at IS NULL);


--
-- Name: index_active_charge_filters; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_charge_filters ON public.charge_filters USING btree (charge_id) WHERE (deleted_at IS NULL);


--
-- Name: index_active_metric_filters; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_metric_filters ON public.billable_metric_filters USING btree (billable_metric_id) WHERE (deleted_at IS NULL);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_add_ons_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_add_ons_on_deleted_at ON public.add_ons USING btree (deleted_at);


--
-- Name: index_add_ons_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_add_ons_on_organization_id ON public.add_ons USING btree (organization_id);


--
-- Name: index_add_ons_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_add_ons_on_organization_id_and_code ON public.add_ons USING btree (organization_id, code) WHERE (deleted_at IS NULL);


--
-- Name: index_add_ons_taxes_on_add_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_add_ons_taxes_on_add_on_id ON public.add_ons_taxes USING btree (add_on_id);


--
-- Name: index_add_ons_taxes_on_add_on_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_add_ons_taxes_on_add_on_id_and_tax_id ON public.add_ons_taxes USING btree (add_on_id, tax_id);


--
-- Name: index_add_ons_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_add_ons_taxes_on_tax_id ON public.add_ons_taxes USING btree (tax_id);


--
-- Name: index_adjusted_fees_on_charge_filter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_charge_filter_id ON public.adjusted_fees USING btree (charge_filter_id);


--
-- Name: index_adjusted_fees_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_charge_id ON public.adjusted_fees USING btree (charge_id);


--
-- Name: index_adjusted_fees_on_fee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_fee_id ON public.adjusted_fees USING btree (fee_id);


--
-- Name: index_adjusted_fees_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_group_id ON public.adjusted_fees USING btree (group_id);


--
-- Name: index_adjusted_fees_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_invoice_id ON public.adjusted_fees USING btree (invoice_id);


--
-- Name: index_adjusted_fees_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_adjusted_fees_on_subscription_id ON public.adjusted_fees USING btree (subscription_id);


--
-- Name: index_api_keys_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_keys_on_organization_id ON public.api_keys USING btree (organization_id);


--
-- Name: index_api_keys_on_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_keys_on_value ON public.api_keys USING btree (value);


--
-- Name: index_applied_add_ons_on_add_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_add_ons_on_add_on_id ON public.applied_add_ons USING btree (add_on_id);


--
-- Name: index_applied_add_ons_on_add_on_id_and_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_add_ons_on_add_on_id_and_customer_id ON public.applied_add_ons USING btree (add_on_id, customer_id);


--
-- Name: index_applied_add_ons_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_add_ons_on_customer_id ON public.applied_add_ons USING btree (customer_id);


--
-- Name: index_applied_coupons_on_coupon_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_coupons_on_coupon_id ON public.applied_coupons USING btree (coupon_id);


--
-- Name: index_applied_coupons_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_coupons_on_customer_id ON public.applied_coupons USING btree (customer_id);


--
-- Name: index_applied_invoice_custom_sections_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_invoice_custom_sections_on_invoice_id ON public.applied_invoice_custom_sections USING btree (invoice_id);


--
-- Name: index_applied_usage_thresholds_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_usage_thresholds_on_invoice_id ON public.applied_usage_thresholds USING btree (invoice_id);


--
-- Name: index_applied_usage_thresholds_on_usage_threshold_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_applied_usage_thresholds_on_usage_threshold_id ON public.applied_usage_thresholds USING btree (usage_threshold_id);


--
-- Name: index_billable_metric_filters_on_billable_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billable_metric_filters_on_billable_metric_id ON public.billable_metric_filters USING btree (billable_metric_id);


--
-- Name: index_billable_metric_filters_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billable_metric_filters_on_deleted_at ON public.billable_metric_filters USING btree (deleted_at);


--
-- Name: index_billable_metrics_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billable_metrics_on_deleted_at ON public.billable_metrics USING btree (deleted_at);


--
-- Name: index_billable_metrics_on_org_id_and_code_and_expr; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billable_metrics_on_org_id_and_code_and_expr ON public.billable_metrics USING btree (organization_id, code, expression) WHERE ((expression IS NOT NULL) AND ((expression)::text <> ''::text));


--
-- Name: index_billable_metrics_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billable_metrics_on_organization_id ON public.billable_metrics USING btree (organization_id);


--
-- Name: index_billable_metrics_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billable_metrics_on_organization_id_and_code ON public.billable_metrics USING btree (organization_id, code) WHERE (deleted_at IS NULL);


--
-- Name: index_cached_aggregations_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_charge_id ON public.cached_aggregations USING btree (charge_id);


--
-- Name: index_cached_aggregations_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_event_id ON public.cached_aggregations USING btree (event_id);


--
-- Name: index_cached_aggregations_on_event_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_event_transaction_id ON public.cached_aggregations USING btree (organization_id, event_transaction_id);


--
-- Name: index_cached_aggregations_on_external_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_external_subscription_id ON public.cached_aggregations USING btree (external_subscription_id);


--
-- Name: index_cached_aggregations_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_group_id ON public.cached_aggregations USING btree (group_id);


--
-- Name: index_cached_aggregations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cached_aggregations_on_organization_id ON public.cached_aggregations USING btree (organization_id);


--
-- Name: index_charge_filter_values_on_billable_metric_filter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charge_filter_values_on_billable_metric_filter_id ON public.charge_filter_values USING btree (billable_metric_filter_id);


--
-- Name: index_charge_filter_values_on_charge_filter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charge_filter_values_on_charge_filter_id ON public.charge_filter_values USING btree (charge_filter_id);


--
-- Name: index_charge_filter_values_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charge_filter_values_on_deleted_at ON public.charge_filter_values USING btree (deleted_at);


--
-- Name: index_charge_filters_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charge_filters_on_charge_id ON public.charge_filters USING btree (charge_id);


--
-- Name: index_charge_filters_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charge_filters_on_deleted_at ON public.charge_filters USING btree (deleted_at);


--
-- Name: index_charges_on_billable_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_on_billable_metric_id ON public.charges USING btree (billable_metric_id) WHERE (deleted_at IS NULL);


--
-- Name: index_charges_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_on_deleted_at ON public.charges USING btree (deleted_at);


--
-- Name: index_charges_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_on_parent_id ON public.charges USING btree (parent_id);


--
-- Name: index_charges_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_on_plan_id ON public.charges USING btree (plan_id);


--
-- Name: index_charges_taxes_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_taxes_on_charge_id ON public.charges_taxes USING btree (charge_id);


--
-- Name: index_charges_taxes_on_charge_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_charges_taxes_on_charge_id_and_tax_id ON public.charges_taxes USING btree (charge_id, tax_id);


--
-- Name: index_charges_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_charges_taxes_on_tax_id ON public.charges_taxes USING btree (tax_id);


--
-- Name: index_commitments_on_commitment_type_and_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_commitments_on_commitment_type_and_plan_id ON public.commitments USING btree (commitment_type, plan_id);


--
-- Name: index_commitments_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_commitments_on_plan_id ON public.commitments USING btree (plan_id);


--
-- Name: index_commitments_taxes_on_commitment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_commitments_taxes_on_commitment_id ON public.commitments_taxes USING btree (commitment_id);


--
-- Name: index_commitments_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_commitments_taxes_on_tax_id ON public.commitments_taxes USING btree (tax_id);


--
-- Name: index_coupon_targets_on_billable_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupon_targets_on_billable_metric_id ON public.coupon_targets USING btree (billable_metric_id);


--
-- Name: index_coupon_targets_on_coupon_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupon_targets_on_coupon_id ON public.coupon_targets USING btree (coupon_id);


--
-- Name: index_coupon_targets_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupon_targets_on_deleted_at ON public.coupon_targets USING btree (deleted_at);


--
-- Name: index_coupon_targets_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupon_targets_on_plan_id ON public.coupon_targets USING btree (plan_id);


--
-- Name: index_coupons_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupons_on_deleted_at ON public.coupons USING btree (deleted_at);


--
-- Name: index_coupons_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupons_on_organization_id ON public.coupons USING btree (organization_id);


--
-- Name: index_coupons_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_coupons_on_organization_id_and_code ON public.coupons USING btree (organization_id, code) WHERE (deleted_at IS NULL);


--
-- Name: index_credit_note_items_on_credit_note_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_note_items_on_credit_note_id ON public.credit_note_items USING btree (credit_note_id);


--
-- Name: index_credit_note_items_on_fee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_note_items_on_fee_id ON public.credit_note_items USING btree (fee_id);


--
-- Name: index_credit_notes_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_notes_on_customer_id ON public.credit_notes USING btree (customer_id);


--
-- Name: index_credit_notes_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_notes_on_invoice_id ON public.credit_notes USING btree (invoice_id);


--
-- Name: index_credit_notes_taxes_on_credit_note_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_notes_taxes_on_credit_note_id ON public.credit_notes_taxes USING btree (credit_note_id);


--
-- Name: index_credit_notes_taxes_on_credit_note_id_and_tax_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_credit_notes_taxes_on_credit_note_id_and_tax_code ON public.credit_notes_taxes USING btree (credit_note_id, tax_code);


--
-- Name: index_credit_notes_taxes_on_tax_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_notes_taxes_on_tax_code ON public.credit_notes_taxes USING btree (tax_code);


--
-- Name: index_credit_notes_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credit_notes_taxes_on_tax_id ON public.credit_notes_taxes USING btree (tax_id);


--
-- Name: index_credits_on_applied_coupon_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credits_on_applied_coupon_id ON public.credits USING btree (applied_coupon_id);


--
-- Name: index_credits_on_credit_note_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credits_on_credit_note_id ON public.credits USING btree (credit_note_id);


--
-- Name: index_credits_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credits_on_invoice_id ON public.credits USING btree (invoice_id);


--
-- Name: index_credits_on_progressive_billing_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_credits_on_progressive_billing_invoice_id ON public.credits USING btree (progressive_billing_invoice_id);


--
-- Name: index_customer_metadata_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customer_metadata_on_customer_id ON public.customer_metadata USING btree (customer_id);


--
-- Name: index_customer_metadata_on_customer_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customer_metadata_on_customer_id_and_key ON public.customer_metadata USING btree (customer_id, key);


--
-- Name: index_customers_on_applied_dunning_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_applied_dunning_campaign_id ON public.customers USING btree (applied_dunning_campaign_id);


--
-- Name: index_customers_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_deleted_at ON public.customers USING btree (deleted_at);


--
-- Name: index_customers_on_external_id_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_external_id_and_organization_id ON public.customers USING btree (external_id, organization_id) WHERE (deleted_at IS NULL);


--
-- Name: index_customers_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_on_organization_id ON public.customers USING btree (organization_id);


--
-- Name: index_customers_taxes_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_taxes_on_customer_id ON public.customers_taxes USING btree (customer_id);


--
-- Name: index_customers_taxes_on_customer_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_taxes_on_customer_id_and_tax_id ON public.customers_taxes USING btree (customer_id, tax_id);


--
-- Name: index_customers_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_customers_taxes_on_tax_id ON public.customers_taxes USING btree (tax_id);


--
-- Name: index_daily_usages_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_usages_on_customer_id ON public.daily_usages USING btree (customer_id);


--
-- Name: index_daily_usages_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_usages_on_organization_id ON public.daily_usages USING btree (organization_id);


--
-- Name: index_daily_usages_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_usages_on_subscription_id ON public.daily_usages USING btree (subscription_id);


--
-- Name: index_data_export_parts_on_data_export_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_export_parts_on_data_export_id ON public.data_export_parts USING btree (data_export_id);


--
-- Name: index_data_exports_on_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_exports_on_membership_id ON public.data_exports USING btree (membership_id);


--
-- Name: index_data_exports_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_exports_on_organization_id ON public.data_exports USING btree (organization_id);


--
-- Name: index_dunning_campaign_thresholds_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dunning_campaign_thresholds_on_deleted_at ON public.dunning_campaign_thresholds USING btree (deleted_at);


--
-- Name: index_dunning_campaign_thresholds_on_dunning_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dunning_campaign_thresholds_on_dunning_campaign_id ON public.dunning_campaign_thresholds USING btree (dunning_campaign_id);


--
-- Name: index_dunning_campaigns_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dunning_campaigns_on_deleted_at ON public.dunning_campaigns USING btree (deleted_at);


--
-- Name: index_dunning_campaigns_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dunning_campaigns_on_organization_id ON public.dunning_campaigns USING btree (organization_id);


--
-- Name: index_dunning_campaigns_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dunning_campaigns_on_organization_id_and_code ON public.dunning_campaigns USING btree (organization_id, code) WHERE (deleted_at IS NULL);


--
-- Name: index_error_details_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_details_on_deleted_at ON public.error_details USING btree (deleted_at);


--
-- Name: index_error_details_on_error_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_details_on_error_code ON public.error_details USING btree (error_code);


--
-- Name: index_error_details_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_details_on_organization_id ON public.error_details USING btree (organization_id);


--
-- Name: index_error_details_on_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_error_details_on_owner ON public.error_details USING btree (owner_type, owner_id);


--
-- Name: index_events_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_customer_id ON public.events USING btree (customer_id);


--
-- Name: index_events_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_deleted_at ON public.events USING btree (deleted_at);


--
-- Name: index_events_on_external_subscription_id_and_code_and_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_external_subscription_id_and_code_and_timestamp ON public.events USING btree (organization_id, external_subscription_id, code, "timestamp") WHERE (deleted_at IS NULL);


--
-- Name: index_events_on_external_subscription_id_precise_amount; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_external_subscription_id_precise_amount ON public.events USING btree (external_subscription_id, code, "timestamp") INCLUDE (organization_id, precise_total_amount_cents) WHERE ((deleted_at IS NULL) AND (precise_total_amount_cents IS NOT NULL));


--
-- Name: index_events_on_external_subscription_id_with_included; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_external_subscription_id_with_included ON public.events USING btree (external_subscription_id, code, "timestamp") INCLUDE (organization_id, properties) WHERE (deleted_at IS NULL);


--
-- Name: index_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id ON public.events USING btree (organization_id);


--
-- Name: index_events_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id_and_code ON public.events USING btree (organization_id, code);


--
-- Name: index_events_on_organization_id_and_code_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id_and_code_and_created_at ON public.events USING btree (organization_id, code, created_at) WHERE (deleted_at IS NULL);


--
-- Name: index_events_on_organization_id_and_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id_and_timestamp ON public.events USING btree (organization_id, "timestamp") WHERE (deleted_at IS NULL);


--
-- Name: index_events_on_properties; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_properties ON public.events USING gin (properties jsonb_path_ops);


--
-- Name: index_events_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_subscription_id ON public.events USING btree (subscription_id);


--
-- Name: index_events_on_subscription_id_and_code_and_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_subscription_id_and_code_and_timestamp ON public.events USING btree (subscription_id, code, "timestamp") WHERE (deleted_at IS NULL);


--
-- Name: index_fees_on_add_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_add_on_id ON public.fees USING btree (add_on_id);


--
-- Name: index_fees_on_applied_add_on_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_applied_add_on_id ON public.fees USING btree (applied_add_on_id);


--
-- Name: index_fees_on_charge_filter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_charge_filter_id ON public.fees USING btree (charge_filter_id);


--
-- Name: index_fees_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_charge_id ON public.fees USING btree (charge_id);


--
-- Name: index_fees_on_charge_id_and_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_charge_id_and_invoice_id ON public.fees USING btree (charge_id, invoice_id) WHERE (deleted_at IS NULL);


--
-- Name: index_fees_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_deleted_at ON public.fees USING btree (deleted_at);


--
-- Name: index_fees_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_group_id ON public.fees USING btree (group_id);


--
-- Name: index_fees_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_invoice_id ON public.fees USING btree (invoice_id);


--
-- Name: index_fees_on_invoiceable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_invoiceable ON public.fees USING btree (invoiceable_type, invoiceable_id);


--
-- Name: index_fees_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_organization_id ON public.fees USING btree (organization_id);


--
-- Name: index_fees_on_pay_in_advance_event_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_pay_in_advance_event_transaction_id ON public.fees USING btree (pay_in_advance_event_transaction_id) WHERE (deleted_at IS NULL);


--
-- Name: index_fees_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_subscription_id ON public.fees USING btree (subscription_id);


--
-- Name: index_fees_on_true_up_parent_fee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_on_true_up_parent_fee_id ON public.fees USING btree (true_up_parent_fee_id);


--
-- Name: index_fees_taxes_on_fee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_taxes_on_fee_id ON public.fees_taxes USING btree (fee_id);


--
-- Name: index_fees_taxes_on_fee_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_fees_taxes_on_fee_id_and_tax_id ON public.fees_taxes USING btree (fee_id, tax_id) WHERE ((tax_id IS NOT NULL) AND (created_at >= '2023-09-12 00:00:00'::timestamp without time zone));


--
-- Name: index_fees_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_fees_taxes_on_tax_id ON public.fees_taxes USING btree (tax_id);


--
-- Name: index_group_properties_on_charge_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_group_properties_on_charge_id ON public.group_properties USING btree (charge_id);


--
-- Name: index_group_properties_on_charge_id_and_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_group_properties_on_charge_id_and_group_id ON public.group_properties USING btree (charge_id, group_id);


--
-- Name: index_group_properties_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_group_properties_on_deleted_at ON public.group_properties USING btree (deleted_at);


--
-- Name: index_group_properties_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_group_properties_on_group_id ON public.group_properties USING btree (group_id);


--
-- Name: index_groups_on_billable_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_groups_on_billable_metric_id ON public.groups USING btree (billable_metric_id);


--
-- Name: index_groups_on_billable_metric_id_and_parent_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_groups_on_billable_metric_id_and_parent_group_id ON public.groups USING btree (billable_metric_id, parent_group_id);


--
-- Name: index_groups_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_groups_on_deleted_at ON public.groups USING btree (deleted_at);


--
-- Name: index_groups_on_parent_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_groups_on_parent_group_id ON public.groups USING btree (parent_group_id);


--
-- Name: index_int_collection_mappings_on_mapping_type_and_int_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_int_collection_mappings_on_mapping_type_and_int_id ON public.integration_collection_mappings USING btree (mapping_type, integration_id);


--
-- Name: index_int_items_on_external_id_and_int_id_and_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_int_items_on_external_id_and_int_id_and_type ON public.integration_items USING btree (external_id, integration_id, item_type);


--
-- Name: index_integration_collection_mappings_on_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_collection_mappings_on_integration_id ON public.integration_collection_mappings USING btree (integration_id);


--
-- Name: index_integration_customers_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_customers_on_customer_id ON public.integration_customers USING btree (customer_id);


--
-- Name: index_integration_customers_on_customer_id_and_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_integration_customers_on_customer_id_and_type ON public.integration_customers USING btree (customer_id, type);


--
-- Name: index_integration_customers_on_external_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_customers_on_external_customer_id ON public.integration_customers USING btree (external_customer_id);


--
-- Name: index_integration_customers_on_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_customers_on_integration_id ON public.integration_customers USING btree (integration_id);


--
-- Name: index_integration_items_on_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_items_on_integration_id ON public.integration_items USING btree (integration_id);


--
-- Name: index_integration_mappings_on_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_mappings_on_integration_id ON public.integration_mappings USING btree (integration_id);


--
-- Name: index_integration_mappings_on_mappable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_mappings_on_mappable ON public.integration_mappings USING btree (mappable_type, mappable_id);


--
-- Name: index_integration_resources_on_integration_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_resources_on_integration_id ON public.integration_resources USING btree (integration_id);


--
-- Name: index_integration_resources_on_syncable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integration_resources_on_syncable ON public.integration_resources USING btree (syncable_type, syncable_id);


--
-- Name: index_integrations_on_code_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_integrations_on_code_and_organization_id ON public.integrations USING btree (code, organization_id);


--
-- Name: index_integrations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_integrations_on_organization_id ON public.integrations USING btree (organization_id);


--
-- Name: index_invites_on_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invites_on_membership_id ON public.invites USING btree (membership_id);


--
-- Name: index_invites_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invites_on_organization_id ON public.invites USING btree (organization_id);


--
-- Name: index_invites_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invites_on_token ON public.invites USING btree (token);


--
-- Name: index_invoice_custom_section_selections_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_custom_section_selections_on_customer_id ON public.invoice_custom_section_selections USING btree (customer_id);


--
-- Name: index_invoice_custom_section_selections_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_custom_section_selections_on_organization_id ON public.invoice_custom_section_selections USING btree (organization_id);


--
-- Name: index_invoice_custom_sections_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_custom_sections_on_organization_id ON public.invoice_custom_sections USING btree (organization_id);


--
-- Name: index_invoice_custom_sections_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoice_custom_sections_on_organization_id_and_code ON public.invoice_custom_sections USING btree (organization_id, code);


--
-- Name: index_invoice_metadata_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_metadata_on_invoice_id ON public.invoice_metadata USING btree (invoice_id);


--
-- Name: index_invoice_metadata_on_invoice_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoice_metadata_on_invoice_id_and_key ON public.invoice_metadata USING btree (invoice_id, key);


--
-- Name: index_invoice_subscriptions_boundaries; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_subscriptions_boundaries ON public.invoice_subscriptions USING btree (subscription_id, from_datetime, to_datetime);


--
-- Name: index_invoice_subscriptions_on_charges_from_and_to_datetime; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoice_subscriptions_on_charges_from_and_to_datetime ON public.invoice_subscriptions USING btree (subscription_id, charges_from_datetime, charges_to_datetime) WHERE ((created_at >= '2023-06-09 00:00:00'::timestamp without time zone) AND (recurring IS TRUE));


--
-- Name: index_invoice_subscriptions_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_subscriptions_on_invoice_id ON public.invoice_subscriptions USING btree (invoice_id);


--
-- Name: index_invoice_subscriptions_on_invoice_id_and_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoice_subscriptions_on_invoice_id_and_subscription_id ON public.invoice_subscriptions USING btree (invoice_id, subscription_id) WHERE (created_at >= '2023-11-23 00:00:00'::timestamp without time zone);


--
-- Name: index_invoice_subscriptions_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoice_subscriptions_on_subscription_id ON public.invoice_subscriptions USING btree (subscription_id);


--
-- Name: index_invoices_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_customer_id ON public.invoices USING btree (customer_id);


--
-- Name: index_invoices_on_customer_id_and_sequential_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_on_customer_id_and_sequential_id ON public.invoices USING btree (customer_id, sequential_id);


--
-- Name: index_invoices_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_number ON public.invoices USING btree (number);


--
-- Name: index_invoices_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_organization_id ON public.invoices USING btree (organization_id);


--
-- Name: index_invoices_on_payment_overdue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_payment_overdue ON public.invoices USING btree (payment_overdue);


--
-- Name: index_invoices_on_sequential_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_sequential_id ON public.invoices USING btree (sequential_id);


--
-- Name: index_invoices_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_status ON public.invoices USING btree (status);


--
-- Name: index_invoices_payment_requests_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_payment_requests_on_invoice_id ON public.invoices_payment_requests USING btree (invoice_id);


--
-- Name: index_invoices_payment_requests_on_payment_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_payment_requests_on_payment_request_id ON public.invoices_payment_requests USING btree (payment_request_id);


--
-- Name: index_invoices_taxes_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_taxes_on_invoice_id ON public.invoices_taxes USING btree (invoice_id);


--
-- Name: index_invoices_taxes_on_invoice_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_taxes_on_invoice_id_and_tax_id ON public.invoices_taxes USING btree (invoice_id, tax_id) WHERE ((tax_id IS NOT NULL) AND (created_at >= '2023-09-12 00:00:00'::timestamp without time zone));


--
-- Name: index_invoices_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_taxes_on_tax_id ON public.invoices_taxes USING btree (tax_id);


--
-- Name: index_lifetime_usages_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lifetime_usages_on_organization_id ON public.lifetime_usages USING btree (organization_id);


--
-- Name: index_lifetime_usages_on_recalculate_current_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lifetime_usages_on_recalculate_current_usage ON public.lifetime_usages USING btree (recalculate_current_usage) WHERE ((deleted_at IS NULL) AND (recalculate_current_usage = true));


--
-- Name: index_lifetime_usages_on_recalculate_invoiced_usage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lifetime_usages_on_recalculate_invoiced_usage ON public.lifetime_usages USING btree (recalculate_invoiced_usage) WHERE ((deleted_at IS NULL) AND (recalculate_invoiced_usage = true));


--
-- Name: index_lifetime_usages_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lifetime_usages_on_subscription_id ON public.lifetime_usages USING btree (subscription_id);


--
-- Name: index_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_organization_id ON public.memberships USING btree (organization_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_memberships_on_user_id_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_user_id_and_organization_id ON public.memberships USING btree (user_id, organization_id) WHERE (revoked_at IS NULL);


--
-- Name: index_organizations_on_api_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_api_key ON public.organizations USING btree (api_key);


--
-- Name: index_organizations_on_hmac_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_hmac_key ON public.organizations USING btree (hmac_key);


--
-- Name: index_password_resets_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_password_resets_on_token ON public.password_resets USING btree (token);


--
-- Name: index_password_resets_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_password_resets_on_user_id ON public.password_resets USING btree (user_id);


--
-- Name: index_payment_provider_customers_on_customer_id_and_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_provider_customers_on_customer_id_and_type ON public.payment_provider_customers USING btree (customer_id, type) WHERE (deleted_at IS NULL);


--
-- Name: index_payment_provider_customers_on_payment_provider_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_provider_customers_on_payment_provider_id ON public.payment_provider_customers USING btree (payment_provider_id);


--
-- Name: index_payment_provider_customers_on_provider_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_provider_customers_on_provider_customer_id ON public.payment_provider_customers USING btree (provider_customer_id);


--
-- Name: index_payment_providers_on_code_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payment_providers_on_code_and_organization_id ON public.payment_providers USING btree (code, organization_id) WHERE (deleted_at IS NULL);


--
-- Name: index_payment_providers_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_providers_on_organization_id ON public.payment_providers USING btree (organization_id);


--
-- Name: index_payment_requests_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_requests_on_customer_id ON public.payment_requests USING btree (customer_id);


--
-- Name: index_payment_requests_on_dunning_campaign_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_requests_on_dunning_campaign_id ON public.payment_requests USING btree (dunning_campaign_id);


--
-- Name: index_payment_requests_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payment_requests_on_organization_id ON public.payment_requests USING btree (organization_id);


--
-- Name: index_payments_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_invoice_id ON public.payments USING btree (invoice_id);


--
-- Name: index_payments_on_payable_id_and_payable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_payments_on_payable_id_and_payable_type ON public.payments USING btree (payable_id, payable_type) WHERE (payable_payment_status = ANY (ARRAY['pending'::public.payment_payable_payment_status, 'processing'::public.payment_payable_payment_status]));


--
-- Name: index_payments_on_payable_type_and_payable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_payable_type_and_payable_id ON public.payments USING btree (payable_type, payable_id);


--
-- Name: index_payments_on_payment_provider_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_payment_provider_customer_id ON public.payments USING btree (payment_provider_customer_id);


--
-- Name: index_payments_on_payment_provider_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_payments_on_payment_provider_id ON public.payments USING btree (payment_provider_id);


--
-- Name: index_plans_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_on_created_at ON public.plans USING btree (created_at);


--
-- Name: index_plans_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_on_deleted_at ON public.plans USING btree (deleted_at);


--
-- Name: index_plans_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_on_organization_id ON public.plans USING btree (organization_id);


--
-- Name: index_plans_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_organization_id_and_code ON public.plans USING btree (organization_id, code) WHERE ((deleted_at IS NULL) AND (parent_id IS NULL));


--
-- Name: index_plans_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_on_parent_id ON public.plans USING btree (parent_id);


--
-- Name: index_plans_taxes_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_taxes_on_plan_id ON public.plans_taxes USING btree (plan_id);


--
-- Name: index_plans_taxes_on_plan_id_and_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_taxes_on_plan_id_and_tax_id ON public.plans_taxes USING btree (plan_id, tax_id);


--
-- Name: index_plans_taxes_on_tax_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_plans_taxes_on_tax_id ON public.plans_taxes USING btree (tax_id);


--
-- Name: index_quantified_events_on_billable_metric_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_billable_metric_id ON public.quantified_events USING btree (billable_metric_id);


--
-- Name: index_quantified_events_on_charge_filter_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_charge_filter_id ON public.quantified_events USING btree (charge_filter_id);


--
-- Name: index_quantified_events_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_deleted_at ON public.quantified_events USING btree (deleted_at);


--
-- Name: index_quantified_events_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_external_id ON public.quantified_events USING btree (external_id);


--
-- Name: index_quantified_events_on_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_group_id ON public.quantified_events USING btree (group_id);


--
-- Name: index_quantified_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quantified_events_on_organization_id ON public.quantified_events USING btree (organization_id);


--
-- Name: index_recurring_transaction_rules_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurring_transaction_rules_on_started_at ON public.recurring_transaction_rules USING btree (started_at);


--
-- Name: index_recurring_transaction_rules_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recurring_transaction_rules_on_wallet_id ON public.recurring_transaction_rules USING btree (wallet_id);


--
-- Name: index_refunds_on_credit_note_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_credit_note_id ON public.refunds USING btree (credit_note_id);


--
-- Name: index_refunds_on_payment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_payment_id ON public.refunds USING btree (payment_id);


--
-- Name: index_refunds_on_payment_provider_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_payment_provider_customer_id ON public.refunds USING btree (payment_provider_customer_id);


--
-- Name: index_refunds_on_payment_provider_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_refunds_on_payment_provider_id ON public.refunds USING btree (payment_provider_id);


--
-- Name: index_search_quantified_events; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_search_quantified_events ON public.quantified_events USING btree (organization_id, external_subscription_id, billable_metric_id);


--
-- Name: index_subscriptions_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_customer_id ON public.subscriptions USING btree (customer_id);


--
-- Name: index_subscriptions_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_external_id ON public.subscriptions USING btree (external_id);


--
-- Name: index_subscriptions_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_plan_id ON public.subscriptions USING btree (plan_id);


--
-- Name: index_subscriptions_on_previous_subscription_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_previous_subscription_id_and_status ON public.subscriptions USING btree (previous_subscription_id, status);


--
-- Name: index_subscriptions_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_started_at ON public.subscriptions USING btree (started_at);


--
-- Name: index_subscriptions_on_started_at_and_ending_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_started_at_and_ending_at ON public.subscriptions USING btree (started_at, ending_at);


--
-- Name: index_subscriptions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_status ON public.subscriptions USING btree (status);


--
-- Name: index_taxes_on_code_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_taxes_on_code_and_organization_id ON public.taxes USING btree (code, organization_id);


--
-- Name: index_taxes_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taxes_on_organization_id ON public.taxes USING btree (organization_id);


--
-- Name: index_timestamp_filter_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timestamp_filter_lookup ON public.cached_aggregations USING btree (organization_id, "timestamp", charge_id, charge_filter_id);


--
-- Name: index_timestamp_group_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timestamp_group_lookup ON public.cached_aggregations USING btree (organization_id, "timestamp", charge_id, group_id);


--
-- Name: index_timestamp_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_timestamp_lookup ON public.cached_aggregations USING btree (organization_id, "timestamp", charge_id);


--
-- Name: index_unique_applied_to_organization_per_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unique_applied_to_organization_per_organization ON public.dunning_campaigns USING btree (organization_id) WHERE ((applied_to_organization = true) AND (deleted_at IS NULL));


--
-- Name: index_unique_starting_subscription_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unique_starting_subscription_invoice ON public.invoice_subscriptions USING btree (subscription_id, invoicing_reason) WHERE (invoicing_reason = 'subscription_starting'::public.subscription_invoicing_reason);


--
-- Name: index_unique_terminating_subscription_invoice; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unique_terminating_subscription_invoice ON public.invoice_subscriptions USING btree (subscription_id, invoicing_reason) WHERE (invoicing_reason = 'subscription_terminating'::public.subscription_invoicing_reason);


--
-- Name: index_unique_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unique_transaction_id ON public.events USING btree (organization_id, external_subscription_id, transaction_id);


--
-- Name: index_usage_thresholds_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_usage_thresholds_on_plan_id ON public.usage_thresholds USING btree (plan_id);


--
-- Name: index_usage_thresholds_on_plan_id_and_recurring; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_usage_thresholds_on_plan_id_and_recurring ON public.usage_thresholds USING btree (plan_id, recurring) WHERE ((recurring IS TRUE) AND (deleted_at IS NULL));


--
-- Name: index_versions_on_item_type_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_item_type_and_item_id ON public.versions USING btree (item_type, item_id);


--
-- Name: index_wallet_transactions_on_credit_note_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_credit_note_id ON public.wallet_transactions USING btree (credit_note_id);


--
-- Name: index_wallet_transactions_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_invoice_id ON public.wallet_transactions USING btree (invoice_id);


--
-- Name: index_wallet_transactions_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_wallet_id ON public.wallet_transactions USING btree (wallet_id);


--
-- Name: index_wallets_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_customer_id ON public.wallets USING btree (customer_id);


--
-- Name: index_wallets_on_ready_to_be_refreshed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallets_on_ready_to_be_refreshed ON public.wallets USING btree (ready_to_be_refreshed) WHERE ready_to_be_refreshed;


--
-- Name: index_webhook_endpoints_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_webhook_endpoints_on_organization_id ON public.webhook_endpoints USING btree (organization_id);


--
-- Name: index_webhook_endpoints_on_webhook_url_and_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_webhook_endpoints_on_webhook_url_and_organization_id ON public.webhook_endpoints USING btree (webhook_url, organization_id);


--
-- Name: index_webhooks_on_webhook_endpoint_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_webhooks_on_webhook_endpoint_id ON public.webhooks USING btree (webhook_endpoint_id);


--
-- Name: billable_metrics_grouped_charges _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.billable_metrics_grouped_charges AS
 SELECT billable_metrics.organization_id,
    billable_metrics.code,
    billable_metrics.aggregation_type,
    billable_metrics.field_name,
    charges.plan_id,
    charges.id AS charge_id,
    charges.pay_in_advance,
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
   FROM ((((public.billable_metrics
     JOIN public.charges ON ((charges.billable_metric_id = billable_metrics.id)))
     LEFT JOIN public.charge_filters ON ((charge_filters.charge_id = charges.id)))
     LEFT JOIN public.charge_filter_values ON ((charge_filter_values.charge_filter_id = charge_filters.id)))
     LEFT JOIN public.billable_metric_filters ON ((charge_filter_values.billable_metric_filter_id = billable_metric_filters.id)))
  WHERE ((billable_metrics.deleted_at IS NULL) AND (charges.deleted_at IS NULL) AND (charge_filters.deleted_at IS NULL) AND (charge_filter_values.deleted_at IS NULL) AND (billable_metric_filters.deleted_at IS NULL))
  GROUP BY billable_metrics.organization_id, billable_metrics.code, billable_metrics.aggregation_type, billable_metrics.field_name, charges.plan_id, charges.id, charge_filters.id;


--
-- Name: wallet_transactions fk_rails_01a4c0c7db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_01a4c0c7db FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: fees fk_rails_085d1cc97b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_085d1cc97b FOREIGN KEY (charge_id) REFERENCES public.charges(id);


--
-- Name: add_ons_taxes fk_rails_08dfe87131; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.add_ons_taxes
    ADD CONSTRAINT fk_rails_08dfe87131 FOREIGN KEY (add_on_id) REFERENCES public.add_ons(id);


--
-- Name: invoices fk_rails_0d349e632f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_0d349e632f FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: integration_customers fk_rails_0e464363cb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_customers
    ADD CONSTRAINT fk_rails_0e464363cb FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: applied_invoice_custom_sections fk_rails_10428ecad2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_invoice_custom_sections
    ADD CONSTRAINT fk_rails_10428ecad2 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: daily_usages fk_rails_12d29bc654; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usages
    ADD CONSTRAINT fk_rails_12d29bc654 FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: customer_metadata fk_rails_195153290d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_metadata
    ADD CONSTRAINT fk_rails_195153290d FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: credits fk_rails_1db0057d9b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credits
    ADD CONSTRAINT fk_rails_1db0057d9b FOREIGN KEY (applied_coupon_id) REFERENCES public.applied_coupons(id);


--
-- Name: webhooks fk_rails_20cc0de4c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT fk_rails_20cc0de4c7 FOREIGN KEY (webhook_endpoint_id) REFERENCES public.webhook_endpoints(id);


--
-- Name: plans fk_rails_216ac8a975; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT fk_rails_216ac8a975 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: webhook_endpoints fk_rails_21808fa528; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhook_endpoints
    ADD CONSTRAINT fk_rails_21808fa528 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: cached_aggregations fk_rails_21eb389927; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cached_aggregations
    ADD CONSTRAINT fk_rails_21eb389927 FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: invoices_taxes fk_rails_22af6c6d28; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_taxes
    ADD CONSTRAINT fk_rails_22af6c6d28 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: credit_notes_taxes fk_rails_25232a0ec3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes_taxes
    ADD CONSTRAINT fk_rails_25232a0ec3 FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);


--
-- Name: refunds fk_rails_25267b0e17; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_25267b0e17 FOREIGN KEY (payment_id) REFERENCES public.payments(id);


--
-- Name: adjusted_fees fk_rails_2561c00887; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT fk_rails_2561c00887 FOREIGN KEY (fee_id) REFERENCES public.fees(id);


--
-- Name: payment_providers fk_rails_26be2f764d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_providers
    ADD CONSTRAINT fk_rails_26be2f764d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: charge_filters fk_rails_27b55b8574; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_filters
    ADD CONSTRAINT fk_rails_27b55b8574 FOREIGN KEY (charge_id) REFERENCES public.charges(id);


--
-- Name: wallets fk_rails_2b35eef34b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT fk_rails_2b35eef34b FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: refunds fk_rails_2dc6171f57; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_2dc6171f57 FOREIGN KEY (payment_provider_id) REFERENCES public.payment_providers(id);


--
-- Name: fees fk_rails_2ea4db3a4c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_2ea4db3a4c FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: payment_requests fk_rails_2fb2147151; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_requests
    ADD CONSTRAINT fk_rails_2fb2147151 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: credits fk_rails_2fd7ee65e6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credits
    ADD CONSTRAINT fk_rails_2fd7ee65e6 FOREIGN KEY (progressive_billing_invoice_id) REFERENCES public.invoices(id);


--
-- Name: payment_requests fk_rails_32600e5a72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_requests
    ADD CONSTRAINT fk_rails_32600e5a72 FOREIGN KEY (dunning_campaign_id) REFERENCES public.dunning_campaigns(id);


--
-- Name: lifetime_usages fk_rails_348acbd245; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifetime_usages
    ADD CONSTRAINT fk_rails_348acbd245 FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: fees fk_rails_34ab152115; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_34ab152115 FOREIGN KEY (applied_add_on_id) REFERENCES public.applied_add_ons(id);


--
-- Name: groups fk_rails_34b5ee1894; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_rails_34b5ee1894 FOREIGN KEY (billable_metric_id) REFERENCES public.billable_metrics(id) ON DELETE CASCADE;


--
-- Name: customers_taxes fk_rails_3708a65be3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_taxes
    ADD CONSTRAINT fk_rails_3708a65be3 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: fees fk_rails_38047eb662; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_38047eb662 FOREIGN KEY (true_up_parent_fee_id) REFERENCES public.fees(id);


--
-- Name: quantified_events fk_rails_3926855f12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quantified_events
    ADD CONSTRAINT fk_rails_3926855f12 FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: invoices fk_rails_3a303bf667; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_3a303bf667 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: group_properties fk_rails_3acf9e789c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_properties
    ADD CONSTRAINT fk_rails_3acf9e789c FOREIGN KEY (charge_id) REFERENCES public.charges(id) ON DELETE CASCADE;


--
-- Name: daily_usages fk_rails_3c7c3920c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usages
    ADD CONSTRAINT fk_rails_3c7c3920c0 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: charges fk_rails_3cfe1d68d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_rails_3cfe1d68d7 FOREIGN KEY (parent_id) REFERENCES public.charges(id);


--
-- Name: integration_collection_mappings fk_rails_3d568ff9de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_collection_mappings
    ADD CONSTRAINT fk_rails_3d568ff9de FOREIGN KEY (integration_id) REFERENCES public.integrations(id);


--
-- Name: invoices_payment_requests fk_rails_3ec3563cf3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_payment_requests
    ADD CONSTRAINT fk_rails_3ec3563cf3 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: refunds fk_rails_3f7be5debc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_3f7be5debc FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);


--
-- Name: charges_taxes fk_rails_3ff27d7624; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges_taxes
    ADD CONSTRAINT fk_rails_3ff27d7624 FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: credit_notes fk_rails_4117574b51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT fk_rails_4117574b51 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: usage_thresholds fk_rails_450b79f2a9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_thresholds
    ADD CONSTRAINT fk_rails_450b79f2a9 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: payment_provider_customers fk_rails_50d46d3679; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_customers
    ADD CONSTRAINT fk_rails_50d46d3679 FOREIGN KEY (payment_provider_id) REFERENCES public.payment_providers(id);


--
-- Name: commitments fk_rails_51ac39a0c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments
    ADD CONSTRAINT fk_rails_51ac39a0c6 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: credits fk_rails_521b5240ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credits
    ADD CONSTRAINT fk_rails_521b5240ed FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: password_resets fk_rails_526379cd99; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT fk_rails_526379cd99 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: applied_usage_thresholds fk_rails_52b72c9b0e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_usage_thresholds
    ADD CONSTRAINT fk_rails_52b72c9b0e FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: customers fk_rails_58234c715e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_58234c715e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: data_exports fk_rails_5a43da571b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_exports
    ADD CONSTRAINT fk_rails_5a43da571b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: error_details fk_rails_5c21eece29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.error_details
    ADD CONSTRAINT fk_rails_5c21eece29 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: credit_notes fk_rails_5cb67dee79; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes
    ADD CONSTRAINT fk_rails_5cb67dee79 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: coupon_targets fk_rails_5fce5ea2b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_targets
    ADD CONSTRAINT fk_rails_5fce5ea2b5 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: fees fk_rails_6023b3f2dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_6023b3f2dd FOREIGN KEY (add_on_id) REFERENCES public.add_ons(id);


--
-- Name: credit_notes_taxes fk_rails_626209b8d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_notes_taxes
    ADD CONSTRAINT fk_rails_626209b8d2 FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: payments fk_rails_62d18ea517; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_rails_62d18ea517 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: subscriptions fk_rails_63d3df128b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_63d3df128b FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: memberships fk_rails_64267aab58; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_64267aab58 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: taxes fk_rails_65b48ef6bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxes
    ADD CONSTRAINT fk_rails_65b48ef6bf FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: subscriptions fk_rails_66eb6b32c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_66eb6b32c1 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: integration_resources fk_rails_67d4eb3c92; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_resources
    ADD CONSTRAINT fk_rails_67d4eb3c92 FOREIGN KEY (integration_id) REFERENCES public.integrations(id);


--
-- Name: invoice_custom_section_selections fk_rails_6b1e3d1159; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_section_selections
    ADD CONSTRAINT fk_rails_6b1e3d1159 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: dunning_campaigns fk_rails_6c720a8ccd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_campaigns
    ADD CONSTRAINT fk_rails_6c720a8ccd FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: adjusted_fees fk_rails_6d465e6b10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT fk_rails_6d465e6b10 FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: invoices_taxes fk_rails_6e148ccbb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_taxes
    ADD CONSTRAINT fk_rails_6e148ccbb1 FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: data_exports fk_rails_73d83e23b6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_exports
    ADD CONSTRAINT fk_rails_73d83e23b6 FOREIGN KEY (membership_id) REFERENCES public.memberships(id);


--
-- Name: fees_taxes fk_rails_745b4ca7dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees_taxes
    ADD CONSTRAINT fk_rails_745b4ca7dd FOREIGN KEY (fee_id) REFERENCES public.fees(id);


--
-- Name: refunds fk_rails_75577c354e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT fk_rails_75577c354e FOREIGN KEY (payment_provider_customer_id) REFERENCES public.payment_provider_customers(id);


--
-- Name: integrations fk_rails_755d734f25; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT fk_rails_755d734f25 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: groups fk_rails_7886e1bc34; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT fk_rails_7886e1bc34 FOREIGN KEY (parent_group_id) REFERENCES public.groups(id);


--
-- Name: applied_add_ons fk_rails_7995206484; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_add_ons
    ADD CONSTRAINT fk_rails_7995206484 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: billable_metric_filters fk_rails_7a0704ce72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billable_metric_filters
    ADD CONSTRAINT fk_rails_7a0704ce72 FOREIGN KEY (billable_metric_id) REFERENCES public.billable_metrics(id);


--
-- Name: api_keys fk_rails_7aab96f30e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT fk_rails_7aab96f30e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: adjusted_fees fk_rails_7b324610ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT fk_rails_7b324610ad FOREIGN KEY (charge_id) REFERENCES public.charges(id);


--
-- Name: invoice_custom_sections fk_rails_7c0e340dbd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_sections
    ADD CONSTRAINT fk_rails_7c0e340dbd FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: charge_filter_values fk_rails_7da558cadc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_filter_values
    ADD CONSTRAINT fk_rails_7da558cadc FOREIGN KEY (charge_filter_id) REFERENCES public.charge_filters(id);


--
-- Name: billable_metrics fk_rails_7e8a2f26e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billable_metrics
    ADD CONSTRAINT fk_rails_7e8a2f26e5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: charges fk_rails_7eb0484711; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_rails_7eb0484711 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: add_ons fk_rails_81e3b6abba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.add_ons
    ADD CONSTRAINT fk_rails_81e3b6abba FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: payments fk_rails_84f4587409; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT fk_rails_84f4587409 FOREIGN KEY (payment_provider_id) REFERENCES public.payment_providers(id);


--
-- Name: payment_provider_customers fk_rails_86676be631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_provider_customers
    ADD CONSTRAINT fk_rails_86676be631 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: invoice_subscriptions fk_rails_88349fc20a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_subscriptions
    ADD CONSTRAINT fk_rails_88349fc20a FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: coupon_targets fk_rails_8872c07e0d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_targets
    ADD CONSTRAINT fk_rails_8872c07e0d FOREIGN KEY (billable_metric_id) REFERENCES public.billable_metrics(id);


--
-- Name: add_ons_taxes fk_rails_89e1020aca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.add_ons_taxes
    ADD CONSTRAINT fk_rails_89e1020aca FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: invoice_metadata fk_rails_8bb5b094c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_metadata
    ADD CONSTRAINT fk_rails_8bb5b094c4 FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: credits fk_rails_8ca834cd4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credits
    ADD CONSTRAINT fk_rails_8ca834cd4a FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);


--
-- Name: commitments_taxes fk_rails_8fa6f0d920; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments_taxes
    ADD CONSTRAINT fk_rails_8fa6f0d920 FOREIGN KEY (commitment_id) REFERENCES public.commitments(id);


--
-- Name: invoice_subscriptions fk_rails_90d93bd016; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_subscriptions
    ADD CONSTRAINT fk_rails_90d93bd016 FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- Name: data_export_parts fk_rails_9298b8fdad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_export_parts
    ADD CONSTRAINT fk_rails_9298b8fdad FOREIGN KEY (data_export_id) REFERENCES public.data_exports(id);


--
-- Name: customers fk_rails_94cc21031f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_rails_94cc21031f FOREIGN KEY (applied_dunning_campaign_id) REFERENCES public.dunning_campaigns(id);


--
-- Name: adjusted_fees fk_rails_98980b326b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT fk_rails_98980b326b FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: applied_usage_thresholds fk_rails_9c08b43701; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_usage_thresholds
    ADD CONSTRAINT fk_rails_9c08b43701 FOREIGN KEY (usage_threshold_id) REFERENCES public.usage_thresholds(id);


--
-- Name: plans_taxes fk_rails_9c704027e2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans_taxes
    ADD CONSTRAINT fk_rails_9c704027e2 FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: applied_add_ons fk_rails_9c8e276cc0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applied_add_ons
    ADD CONSTRAINT fk_rails_9c8e276cc0 FOREIGN KEY (add_on_id) REFERENCES public.add_ons(id);


--
-- Name: wallet_transactions fk_rails_9ea6759859; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_9ea6759859 FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);


--
-- Name: credit_note_items fk_rails_9f22076477; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT fk_rails_9f22076477 FOREIGN KEY (credit_note_id) REFERENCES public.credit_notes(id);


--
-- Name: invoice_custom_section_selections fk_rails_9ff1d277f3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_section_selections
    ADD CONSTRAINT fk_rails_9ff1d277f3 FOREIGN KEY (invoice_custom_section_id) REFERENCES public.invoice_custom_sections(id);


--
-- Name: group_properties fk_rails_a2d2cb3819; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.group_properties
    ADD CONSTRAINT fk_rails_a2d2cb3819 FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;


--
-- Name: charges fk_rails_a710519346; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges
    ADD CONSTRAINT fk_rails_a710519346 FOREIGN KEY (billable_metric_id) REFERENCES public.billable_metrics(id);


--
-- Name: integration_items fk_rails_a9dc2ea536; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_items
    ADD CONSTRAINT fk_rails_a9dc2ea536 FOREIGN KEY (integration_id) REFERENCES public.integrations(id);


--
-- Name: commitments_taxes fk_rails_aaa12f7d3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.commitments_taxes
    ADD CONSTRAINT fk_rails_aaa12f7d3e FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: charges_taxes fk_rails_ac146c9541; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charges_taxes
    ADD CONSTRAINT fk_rails_ac146c9541 FOREIGN KEY (charge_id) REFERENCES public.charges(id);


--
-- Name: daily_usages fk_rails_b07fc711f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_usages
    ADD CONSTRAINT fk_rails_b07fc711f7 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: fees fk_rails_b50dc82c1e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_b50dc82c1e FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: lifetime_usages fk_rails_ba128983c2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifetime_usages
    ADD CONSTRAINT fk_rails_ba128983c2 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: plans_taxes fk_rails_bacde7a063; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans_taxes
    ADD CONSTRAINT fk_rails_bacde7a063 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: dunning_campaign_thresholds fk_rails_bf1f386f75; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dunning_campaign_thresholds
    ADD CONSTRAINT fk_rails_bf1f386f75 FOREIGN KEY (dunning_campaign_id) REFERENCES public.dunning_campaigns(id);


--
-- Name: charge_filter_values fk_rails_bf661ef73d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.charge_filter_values
    ADD CONSTRAINT fk_rails_bf661ef73d FOREIGN KEY (billable_metric_filter_id) REFERENCES public.billable_metric_filters(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: invites fk_rails_c71f4b2026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT fk_rails_c71f4b2026 FOREIGN KEY (membership_id) REFERENCES public.memberships(id);


--
-- Name: plans fk_rails_cbf700aeb8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT fk_rails_cbf700aeb8 FOREIGN KEY (parent_id) REFERENCES public.plans(id);


--
-- Name: integration_mappings fk_rails_cc318ad1ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_mappings
    ADD CONSTRAINT fk_rails_cc318ad1ff FOREIGN KEY (integration_id) REFERENCES public.integrations(id);


--
-- Name: wallet_transactions fk_rails_d07bc24ce3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_d07bc24ce3 FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: coupon_targets fk_rails_d1dc5814e9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_targets
    ADD CONSTRAINT fk_rails_d1dc5814e9 FOREIGN KEY (coupon_id) REFERENCES public.coupons(id);


--
-- Name: fees fk_rails_d9ffb8b4a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_d9ffb8b4a1 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invites fk_rails_dd342449a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT fk_rails_dd342449a6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invoice_custom_section_selections fk_rails_dd7e076158; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoice_custom_section_selections
    ADD CONSTRAINT fk_rails_dd7e076158 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: credit_note_items fk_rails_dea748e529; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_note_items
    ADD CONSTRAINT fk_rails_dea748e529 FOREIGN KEY (fee_id) REFERENCES public.fees(id);


--
-- Name: recurring_transaction_rules fk_rails_e8bac9c5bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recurring_transaction_rules
    ADD CONSTRAINT fk_rails_e8bac9c5bb FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: integration_customers fk_rails_ea80151038; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integration_customers
    ADD CONSTRAINT fk_rails_ea80151038 FOREIGN KEY (integration_id) REFERENCES public.integrations(id);


--
-- Name: fees fk_rails_eaca9421be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fk_rails_eaca9421be FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: invoices_payment_requests fk_rails_ed387e0992; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices_payment_requests
    ADD CONSTRAINT fk_rails_ed387e0992 FOREIGN KEY (payment_request_id) REFERENCES public.payment_requests(id);


--
-- Name: customers_taxes fk_rails_ef731e48be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers_taxes
    ADD CONSTRAINT fk_rails_ef731e48be FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: payment_requests fk_rails_f228550fda; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_requests
    ADD CONSTRAINT fk_rails_f228550fda FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: quantified_events fk_rails_f510acb495; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quantified_events
    ADD CONSTRAINT fk_rails_f510acb495 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: fees_taxes fk_rails_f98413d404; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fees_taxes
    ADD CONSTRAINT fk_rails_f98413d404 FOREIGN KEY (tax_id) REFERENCES public.taxes(id);


--
-- Name: adjusted_fees fk_rails_fd399a23d3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjusted_fees
    ADD CONSTRAINT fk_rails_fd399a23d3 FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20241216140931'),
('20241216110525'),
('20241213142739'),
('20241203141040'),
('20241203140905'),
('20241203135310'),
('20241128132010'),
('20241128091634'),
('20241126141853'),
('20241126103448'),
('20241126102447'),
('20241125194753'),
('20241122141158'),
('20241122140603'),
('20241122134430'),
('20241122111534'),
('20241122105327'),
('20241122105133'),
('20241122104537'),
('20241120094557'),
('20241120090305'),
('20241120085057'),
('20241119114948'),
('20241119110219'),
('20241118165935'),
('20241118103032'),
('20241113181629'),
('20241108103702'),
('20241107093418'),
('20241106104515'),
('20241101151559'),
('20241031123415'),
('20241031102231'),
('20241031095225'),
('20241030123528'),
('20241029141351'),
('20241025081408'),
('20241024082941'),
('20241022144437'),
('20241021140054'),
('20241021095706'),
('20241018112637'),
('20241017082601'),
('20241016133129'),
('20241016104211'),
('20241015132635'),
('20241014093451'),
('20241014000100'),
('20241011123621'),
('20241011123148'),
('20241010055733'),
('20241008080209'),
('20241007092701'),
('20241007083747'),
('20241001112117'),
('20241001105523'),
('20240924114730'),
('20240920091133'),
('20240920084727'),
('20240917145042'),
('20240917144243'),
('20240910111203'),
('20240910093646'),
('20240906170048'),
('20240906154644'),
('20240829093425'),
('20240823092643'),
('20240822142524'),
('20240822082727'),
('20240822080031'),
('20240821174724'),
('20240821172352'),
('20240821093145'),
('20240820125840'),
('20240820090312'),
('20240819092354'),
('20240816075711'),
('20240814144137'),
('20240813121307'),
('20240813095718'),
('20240812130655'),
('20240808132042'),
('20240808085506'),
('20240808080611'),
('20240807113700'),
('20240807100609'),
('20240807072052'),
('20240802115017'),
('20240801142242'),
('20240801134833'),
('20240801134832'),
('20240729154334'),
('20240729152352'),
('20240729151049'),
('20240729134020'),
('20240729133823'),
('20240723150304'),
('20240723150221'),
('20240722201341'),
('20240718105718'),
('20240718080929'),
('20240716154636'),
('20240716153753'),
('20240712090133'),
('20240711094255'),
('20240711091155'),
('20240708195226'),
('20240708081356'),
('20240706204557'),
('20240705125619'),
('20240703061352'),
('20240702081109'),
('20240701184757'),
('20240701083355'),
('20240628083830'),
('20240628083654'),
('20240626094521'),
('20240625090742'),
('20240619082054'),
('20240611074215'),
('20240607095208'),
('20240607095155'),
('20240604141208'),
('20240603095841'),
('20240603080144'),
('20240530123427'),
('20240522105942'),
('20240521143531'),
('20240520115450'),
('20240514081110'),
('20240514072741'),
('20240506085424'),
('20240502095122'),
('20240502075803'),
('20240430133150'),
('20240430100120'),
('20240429141108'),
('20240426143059'),
('20240425131701'),
('20240425082113'),
('20240424124802'),
('20240424110420'),
('20240423155113'),
('20240419085012'),
('20240419071607'),
('20240415122310'),
('20240412133335'),
('20240412085450'),
('20240411114759'),
('20240404123257'),
('20240403084644'),
('20240329112415'),
('20240328153701'),
('20240328075919'),
('20240327071539'),
('20240314172008'),
('20240314170211'),
('20240314165306'),
('20240314163426'),
('20240312141641'),
('20240311091817'),
('20240308150801'),
('20240308104003'),
('20240305164449'),
('20240305093058'),
('20240301133006'),
('20240227161430'),
('20240205160647'),
('20240129155938'),
('20240125080718'),
('20240123104811'),
('20240118141022'),
('20240118140703'),
('20240118135350'),
('20240115130517'),
('20240115102012'),
('20240115094827'),
('20240112091706'),
('20240111155133'),
('20240111151140'),
('20240111140424'),
('20240104152816'),
('20240103125624'),
('20231220140936'),
('20231220115621'),
('20231219121735'),
('20231218170631'),
('20231214133638'),
('20231214103653'),
('20231207095229'),
('20231205153156'),
('20231204151512'),
('20231204131333'),
('20231201091348'),
('20231130085817'),
('20231129145100'),
('20231128092231'),
('20231123105540'),
('20231123095209'),
('20231117123744'),
('20231114092154'),
('20231109154934'),
('20231109141829'),
('20231107110809'),
('20231106145424'),
('20231103144201'),
('20231102154537'),
('20231102141929'),
('20231102085146'),
('20231101080314'),
('20231027144605'),
('20231020091031'),
('20231017082921'),
('20231016115055'),
('20231010090849'),
('20231010085938'),
('20231001070407'),
('20230926144126'),
('20230926132500'),
('20230922064617'),
('20230920083133'),
('20230918090426'),
('20230915135256'),
('20230915120854'),
('20230915073205'),
('20230913123123'),
('20230912082112'),
('20230912082057'),
('20230912082000'),
('20230911185900'),
('20230911083923'),
('20230907153404'),
('20230907064335'),
('20230905081225'),
('20230830120517'),
('20230828085627'),
('20230821135235'),
('20230817092555'),
('20230816091053'),
('20230811120622'),
('20230811081854'),
('20230808144739'),
('20230731135721'),
('20230731095510'),
('20230727163611'),
('20230726171737'),
('20230726165711'),
('20230721073114'),
('20230720204311'),
('20230719100256'),
('20230717090135'),
('20230713122526'),
('20230705213846'),
('20230704150108'),
('20230704144027'),
('20230704112230'),
('20230629100018'),
('20230627080605'),
('20230626124005'),
('20230626123648'),
('20230620211201'),
('20230619101701'),
('20230615183805'),
('20230614191603'),
('20230608154821'),
('20230608133543'),
('20230608085013'),
('20230606164458'),
('20230606085050'),
('20230602090325'),
('20230529093955'),
('20230525154612'),
('20230525122232'),
('20230525120005'),
('20230524130637'),
('20230523140656'),
('20230523094557'),
('20230522113810'),
('20230522093423'),
('20230522091400'),
('20230517093556'),
('20230511124419'),
('20230510113501'),
('20230505093030'),
('20230503143229'),
('20230425130239'),
('20230424210224'),
('20230424154516'),
('20230424150952'),
('20230424092207'),
('20230424091446'),
('20230421094757'),
('20230420120806'),
('20230420114754'),
('20230419123538'),
('20230418151450'),
('20230417140356'),
('20230417131515'),
('20230417122020'),
('20230417094339'),
('20230414130437'),
('20230414074225'),
('20230411085545'),
('20230411083336'),
('20230403094044'),
('20230403093407'),
('20230328161507'),
('20230327134418'),
('20230323112252'),
('20230313145506'),
('20230307131524'),
('20230301122720'),
('20230227145104'),
('20230221102035'),
('20230221070501'),
('20230216145442'),
('20230216140543'),
('20230214145444'),
('20230214100638'),
('20230207110702'),
('20230206143214'),
('20230203132157'),
('20230202163249'),
('20230202150407'),
('20230202110407'),
('20230131152047'),
('20230131144740'),
('20230127140904'),
('20230126103454'),
('20230125104957'),
('20230118100324'),
('20230109095957'),
('20230106152449'),
('20230105094302'),
('20230102150636'),
('20221226091020'),
('20221222164226'),
('20221219111209'),
('20221216154033'),
('20221212153810'),
('20221208142739'),
('20221208140608'),
('20221206094412'),
('20221205112007'),
('20221202130126'),
('20221129133433'),
('20221128132620'),
('20221125111605'),
('20221122163328'),
('20221118093903'),
('20221118084547'),
('20221115160325'),
('20221115155550'),
('20221115135840'),
('20221115110223'),
('20221115100834'),
('20221114102649'),
('20221110151027'),
('20221107151038'),
('20221031144907'),
('20221031141549'),
('20221028160705'),
('20221028124549'),
('20221028091920'),
('20221024090308'),
('20221021135946'),
('20221021135428'),
('20221020093745'),
('20221018144521'),
('20221013140147'),
('20221011133055'),
('20221011083520'),
('20221010142031'),
('20221010083509'),
('20221007075812'),
('20221004092737'),
('20220930143002'),
('20220930134327'),
('20220930123935'),
('20220923092906'),
('20220922105251'),
('20220921095507'),
('20220919133338'),
('20220916131538'),
('20220915092730'),
('20220906130714'),
('20220906065059'),
('20220905142834'),
('20220905095529'),
('20220831113537'),
('20220829094054'),
('20220825051923'),
('20220824113131'),
('20220823145421'),
('20220823135203'),
('20220818151052'),
('20220818141616'),
('20220817095619'),
('20220817092945'),
('20220816120137'),
('20220811155332'),
('20220809083243'),
('20220807210117'),
('20220801101144'),
('20220729062203'),
('20220729055309'),
('20220728144707'),
('20220727161448'),
('20220727132848'),
('20220725152220'),
('20220722123417'),
('20220721150658'),
('20220718124337'),
('20220718083657'),
('20220713171816'),
('20220705155228'),
('20220704145333'),
('20220629133308'),
('20220621153030'),
('20220621090834'),
('20220620150551'),
('20220620141910'),
('20220617124108'),
('20220614110841'),
('20220613130634'),
('20220610143942'),
('20220610134535'),
('20220609080806'),
('20220607082458'),
('20220602145819'),
('20220601150058'),
('20220530091046'),
('20220526101535'),
('20220525122759');

