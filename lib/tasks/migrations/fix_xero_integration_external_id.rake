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

    Integrations::XeroIntegration.find_each do |integration|
      item_count = integration.integration_items.standard.count
      puts "Processing integration #{integration.code} (#{integration.organization.name}) with #{item_count} items..."

      remote_items = []
      cursor = nil

      loop do
        response = fetch_service.call(integration:, cursor:)

        remote_items.concat(response["records"])
        cursor = response["next_cursor"]

        break if cursor.blank?
      end

      # Build mapping from old external_id (Xero id) to new external_id (item_code)
      id_to_item_code = remote_items.to_h { |ri| [ri["id"], ri["item_code"]] }

      item_mapping = integration.integration_items.standard.to_h do |item|
        [item.id, id_to_item_code[item.external_id]]
      end

      missing = {
        integration_items: [],
        integration_mappings: [],
        integration_collection_mappings: []
      }
      integration.integration_items.standard.each do |item|
        next if id_to_item_code.key?(item.external_id)
        missing[:integration_items] << item.id
      end

      integration.integration_mappings.each do |mapping|
        next if id_to_item_code.key?(mapping.external_id)
        missing[:integration_mappings] << mapping.id
      end

      integration.integration_collection_mappings.where.not(mapping_type: :account).find_each do |mapping|
        next if id_to_item_code.key?(mapping.external_id)
        missing[:integration_collection_mappings] << mapping.id
      end

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
        item_mapping.each do |item_id, item_code|
          integration_item = integration.integration_items.find(item_id)
          integration_item.update!(external_id: item_code)
        end

        # Update integration mappings
        integration.integration_mappings.each do |mapping|
          new_item_code = id_to_item_code[mapping.external_id]
          next unless new_item_code

          mapping.external_id = new_item_code
          mapping.save!
        end

        # Update integration collection mappings
        integration.integration_collection_mappings.each do |mapping|
          new_item_code = id_to_item_code[mapping.external_id]
          next unless new_item_code

          mapping.external_id = new_item_code
          mapping.save!
        end
      end

      puts "Processed integration #{integration.code} with #{item_mapping.size} items.\n\n"
    rescue => e
      puts "Error processing integration #{integration.code}: #{e.message}\n\n"
    end
  end
end
