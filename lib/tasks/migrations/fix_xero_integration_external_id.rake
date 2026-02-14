# frozen_string_literal: true

namespace :migrations do
  desc "Migrate Xero integration items external_id from item id to item_code"
  task fix_xero_integration_external_id: :environment do
    fetch_service = Class.new(Integrations::Aggregator::BaseService) do
      def action_path
        "v1/#{provider}/items"
      end

      def initialize(integration:, options: {}, limit: 450, cursor: nil)
        @limit = limit
        @cursor = cursor

        super(integration:, options:)
      end

      def call
        http_client.get(headers:, params:)
      end

      private

      attr_reader :limit, :cursor

      def headers
        {
          "Connection-Id" => integration.connection_id,
          "Authorization" => "Bearer #{secret_key}",
          "Provider-Config-Key" => provider_key
        }
      end

      def params
        {
          limit: limit,
          cursor: cursor
        }.compact
      end
    end

    max_pages = 15

    Integrations::XeroIntegration.find_each do |integration|
      item_count = integration.integration_items.standard.count
      puts "Processing integration #{integration.code} (#{integration.organization.name}) with #{item_count} items..."

      remote_items = []
      cursor = nil

      max_pages.times do
        response = fetch_service.call(integration:, cursor:)

        remote_items.concat(response["records"])
        cursor = response["next_cursor"]

        break if cursor.blank?
      end

      # Build mapping from old external_id (Xero id) to new external_id (item_code)
      id_to_item_code = remote_items.to_h { |ri| [ri["id"], ri["item_code"]] }
      item_code_values = id_to_item_code.values.to_set

      items = integration.integration_items.standard.to_a
      mappings = integration.integration_mappings.to_a
      collection_mappings = integration.integration_collection_mappings.where.not(mapping_type: :account).to_a

      all_external_ids = items.map(&:external_id) +
        mappings.map(&:external_id) +
        collection_mappings.map(&:external_id)

      # Skip if all external_ids are already item_codes (already migrated)
      if all_external_ids.all? { |ext_id| item_code_values.include?(ext_id) }
        puts "Integration #{integration.code} already migrated, skipping.\n\n"
        next
      end

      # Check for unknown external_ids
      missing = {
        integration_items: items.reject { |item| id_to_item_code.key?(item.external_id) }.map(&:id),
        integration_mappings: mappings.reject { |m| id_to_item_code.key?(m.external_id) }.map(&:id),
        integration_collection_mappings: collection_mappings.reject { |m| id_to_item_code.key?(m.external_id) }.map(&:id)
      }

      if missing.values.any?(&:any?)
        puts "Error: Missing remote items for integration #{integration.code}:"
        missing.each do |type, ids|
          next if ids.empty?
          puts "  #{type}: #{ids.join(", ")}"
        end
        puts "Skipping integration #{integration.code} due to missing items.\n\n"
        next
      end

      IntegrationItem.transaction do
        items.each do |item|
          item.update!(external_id: id_to_item_code[item.external_id])
        end

        # Update integration mappings
        mappings.each do |mapping|
          mapping.update!(external_id: id_to_item_code[mapping.external_id])
        end

        # Update integration collection mappings (exclude account mappings)
        collection_mappings.each do |mapping|
          mapping.update!(external_id: id_to_item_code[mapping.external_id])
        end
      end

      updated_count = items.count + mappings.count + collection_mappings.count
      puts "Processed integration #{integration.code} with #{updated_count} items.\n\n"
    rescue => e
      puts "Error processing integration #{integration.code}: #{e.message}\n\n"
    end
  end
end
