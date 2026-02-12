# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:fix_xero_integration_external_id" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:fix_xero_integration_external_id"] }
  let(:organization) { create(:organization) }
  let(:integration) { create(:xero_integration, organization:) }

  let(:remote_items) do
    [
      {"id" => "old-id-1", "item_code" => "new-code-1", "name" => "Item 1", "account_code" => "1000"},
      {"id" => "old-id-2", "item_code" => "new-code-2", "name" => "Item 2", "account_code" => "2000"}
    ]
  end

  let(:api_response) do
    {"records" => remote_items, "next_cursor" => nil}
  end

  before do
    Rake.application.rake_require("tasks/migrations/fix_xero_integration_external_id")
    Rake::Task.define_task(:environment)
    task.reenable

    stub_request(:get, "https://api.nango.dev/v1/xero/items?limit=450")
      .to_return(
        status: 200,
        body: api_response.to_json,
        headers: {"Content-Type" => "application/json"}
      )
  end

  context "when all remote items are found" do
    let!(:item1) do
      create(:integration_item, integration:, organization:, external_id: "old-id-1", item_type: :standard)
    end

    let!(:item2) do
      create(:integration_item, integration:, organization:, external_id: "old-id-2", item_type: :standard)
    end

    it "updates integration items external_id to item_code" do
      expect { task.invoke }.to output(/Processed/).to_stdout

      expect(item1.reload.external_id).to eq("new-code-1")
      expect(item2.reload.external_id).to eq("new-code-2")
    end

    context "with integration mappings referencing old ids" do
      let(:add_on) { create(:add_on, organization:) }

      let!(:mapping) do
        create(:xero_mapping, integration:, organization:, mappable: add_on,
          settings: {"external_id" => "old-id-1", "external_account_code" => "1000", "external_name" => "Item 1"})
      end

      it "updates integration mapping external_id" do
        expect { task.invoke }.to output(/Processed/).to_stdout

        expect(mapping.reload.external_id).to eq("new-code-1")
      end
    end

    context "with integration collection mappings referencing old ids" do
      let!(:collection_mapping) do
        create(:xero_collection_mapping, integration:, organization:, mapping_type: :coupon,
          settings: {"external_id" => "old-id-2", "external_account_code" => "2000", "external_name" => "Item 2"})
      end

      it "updates integration collection mapping external_id" do
        expect { task.invoke }.to output(/Processed/).to_stdout

        expect(collection_mapping.reload.external_id).to eq("new-code-2")
      end
    end

    context "with account collection mappings not in remote items" do
      let!(:account_mapping) do
        create(:xero_collection_mapping, integration:, organization:, mapping_type: :account,
          settings: {"external_id" => "unknown-id", "external_account_code" => "9999", "external_name" => "Account"})
      end

      it "does not flag account mappings as missing and processes the integration" do
        expect { task.invoke }.to output(/Processed/).to_stdout

        expect(account_mapping.reload.external_id).to eq("unknown-id")
      end
    end
  end

  context "when all items, mappings and collection mappings are already migrated" do
    let!(:item1) do
      create(:integration_item, integration:, organization:, external_id: "new-code-1", item_type: :standard)
    end

    let!(:item2) do
      create(:integration_item, integration:, organization:, external_id: "new-code-2", item_type: :standard)
    end

    let(:add_on) { create(:add_on, organization:) }

    let!(:mapping) do
      create(:xero_mapping, integration:, organization:, mappable: add_on,
        settings: {"external_id" => "new-code-1", "external_account_code" => "1000", "external_name" => "Item 1"})
    end

    let!(:collection_mapping) do
      create(:xero_collection_mapping, integration:, organization:, mapping_type: :coupon,
        settings: {"external_id" => "new-code-2", "external_account_code" => "2000", "external_name" => "Item 2"})
    end

    it "skips the integration" do
      expect { task.invoke }.to output(/already migrated/).to_stdout

      expect(item1.reload.external_id).to eq("new-code-1")
      expect(item2.reload.external_id).to eq("new-code-2")
      expect(mapping.reload.external_id).to eq("new-code-1")
      expect(collection_mapping.reload.external_id).to eq("new-code-2")
    end
  end

  context "when a remote item is missing for an integration item" do
    let!(:item_with_unknown_id) do
      create(:integration_item, integration:, organization:, external_id: "unknown-id", item_type: :standard)
    end

    it "skips the integration and logs an error" do
      expect { task.invoke }.to output(/Skipping integration #{integration.code} due to missing items/).to_stdout

      expect(item_with_unknown_id.reload.external_id).to eq("unknown-id")
    end
  end

  context "when a remote item is missing for an integration mapping" do
    let!(:item1) do
      create(:integration_item, integration:, organization:, external_id: "old-id-1", item_type: :standard)
    end

    let(:add_on) { create(:add_on, organization:) }

    let!(:mapping_with_unknown_id) do
      create(:xero_mapping, integration:, organization:, mappable: add_on,
        settings: {"external_id" => "unknown-id", "external_account_code" => "1000", "external_name" => "Item"})
    end

    it "skips the integration and logs an error" do
      expect { task.invoke }.to output(/Skipping integration #{integration.code} due to missing items/).to_stdout

      expect(item1.reload.external_id).to eq("old-id-1")
      expect(mapping_with_unknown_id.reload.external_id).to eq("unknown-id")
    end
  end

  context "when a remote item is missing for a collection mapping" do
    let!(:item1) do
      create(:integration_item, integration:, organization:, external_id: "old-id-1", item_type: :standard)
    end

    let!(:collection_mapping_with_unknown_id) do
      create(:xero_collection_mapping, integration:, organization:, mapping_type: :coupon,
        settings: {"external_id" => "unknown-id", "external_account_code" => "1000", "external_name" => "Item"})
    end

    it "skips the integration and logs an error" do
      expect { task.invoke }.to output(/Skipping integration #{integration.code} due to missing items/).to_stdout

      expect(item1.reload.external_id).to eq("old-id-1")
      expect(collection_mapping_with_unknown_id.reload.external_id).to eq("unknown-id")
    end
  end

  context "when an error occurs during processing" do
    let(:item1) do
      create(:integration_item, integration:, organization:, external_id: "old-id-1", item_type: :standard)
    end

    before do
      item1
      allow(IntegrationItem).to receive(:transaction).and_raise(StandardError.new("db error"))
    end

    it "catches the error and logs it" do
      expect { task.invoke }.to output(/Error processing integration #{integration.code}: db error/).to_stdout
    end
  end

  context "when response has multiple pages" do
    let!(:item1) do
      create(:integration_item, integration:, organization:, external_id: "old-id-1", item_type: :standard)
    end

    let!(:item2) do
      create(:integration_item, integration:, organization:, external_id: "old-id-2", item_type: :standard)
    end

    let(:api_response) do
      {"records" => [remote_items.first], "next_cursor" => "cursor-123"}
    end

    before do
      stub_request(:get, "https://api.nango.dev/v1/xero/items?limit=450&cursor=cursor-123")
        .to_return(
          status: 200,
          body: {"records" => [remote_items.second], "next_cursor" => nil}.to_json,
          headers: {"Content-Type" => "application/json"}
        )
    end

    it "fetches all pages and updates items" do
      expect { task.invoke }.to output(/Processed/).to_stdout

      expect(item1.reload.external_id).to eq("new-code-1")
      expect(item2.reload.external_id).to eq("new-code-2")
    end
  end

  context "when there are no xero integrations" do
    it "does nothing" do
      expect { task.invoke }.not_to output.to_stdout
    end
  end
end
