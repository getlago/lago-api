# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::EnrichedStoreMigration::CheckJob, type: :job do
  let(:organization) { create(:organization) }
  let(:enriched_store_migration) { create(:enriched_store_migration, :checking, organization:) }

  before do
    allow(Events::Stores::Clickhouse::EnrichedStoreMigration::CheckService).to receive(:call!)
  end

  describe "#perform" do
    it "calls the CheckService" do
      described_class.perform_now(enriched_store_migration)

      expect(Events::Stores::Clickhouse::EnrichedStoreMigration::CheckService)
        .to have_received(:call!).with(enriched_store_migration:)
    end
  end
end
