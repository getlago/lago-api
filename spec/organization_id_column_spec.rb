# frozen_string_literal: true

require "rails_helper"

Rspec.describe "All tables must have an organization_id" do
  let(:internal_tables) do
    %w[
      active_storage_attachments
      active_storage_blobs
      active_storage_variant_records
      ar_internal_metadata
      schema_migrations
    ]
  end

  let(:tables_to_skip) do
    %w[
      organizations
      users
      applied_add_ons
      group_properties
      groups
      password_resets
    ]
  end

  let(:tables_to_migrate) do
    %w[
      charge_filter_values
      commitments
      commitments_taxes
      coupon_targets
      credit_note_items
      data_export_parts
      dunning_campaign_thresholds
      integration_collection_mappings
      integration_customers
      integration_items
      integration_mappings
      integration_resources
      recurring_transaction_rules
      refunds
      versions
    ]
  end

  it do
    query = <<~SQL
      SELECT DISTINCT
      	table_name
      FROM
      	information_schema.columns
      WHERE
      	table_schema = 'public'
      	AND table_name NOT IN (
      		SELECT
      			table_name
      		FROM
      			information_schema.columns
      		WHERE
      			table_schema = 'public'
      			AND column_name = 'organization_id'
      	);
    SQL

    tables_without_organization_id = ActiveRecord::Base.connection.execute(query).to_a
      .map { |r| r["table_name"] }
      .reject { |table| internal_tables.include?(table) || tables_to_skip.include?(table) }
      .sort

    expect(tables_without_organization_id).to match_array(tables_to_migrate)
  end
end
