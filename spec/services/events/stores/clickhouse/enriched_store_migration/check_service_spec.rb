# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::EnrichedStoreMigration::CheckService do
  subject(:service) { described_class.new(enriched_store_migration:) }

  let(:organization) { create(:organization) }
  let(:enriched_store_migration) { create(:enriched_store_migration, :checking, organization:) }

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let!(:subscription_with_codes) { create(:subscription, organization:, customer:, plan:) }
  let!(:subscription_without_codes) { create(:subscription, organization:, customer:, plan:) }

  let(:pre_enrichment_check_result) do
    result = Events::Stores::Clickhouse::PreEnrichmentCheckService::Result.new
    result.subscriptions_to_reprocess = {subscription_with_codes.id => ["api_calls"]}
    result
  end

  before do
    allow(Events::Stores::Clickhouse::PreEnrichmentCheckService)
      .to receive(:call).and_return(pre_enrichment_check_result)
    allow(Events::Stores::Clickhouse::EnrichedStoreMigration::SubscriptionOrchestratorJob)
      .to receive(:perform_later)
  end

  describe "#call" do
    context "when migration is in checking state" do
      it "creates subscription migrations for all active subscriptions" do
        result = service.call

        expect(result).to be_success
        expect(result.subscription_migration_count).to eq(2)

        with_codes = enriched_store_migration.subscription_migrations.find_by(subscription: subscription_with_codes)
        expect(with_codes.billable_metric_codes).to eq(["api_calls"])
        expect(with_codes).to be_pending

        without_codes = enriched_store_migration.subscription_migrations.find_by(subscription: subscription_without_codes)
        expect(without_codes.billable_metric_codes).to eq([])
        expect(without_codes).to be_pending
      end

      it "transitions the migration to processing" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_processing
      end

      it "enqueues a SubscriptionOrchestratorJob for each subscription migration" do
        service.call

        enriched_store_migration.subscription_migrations.each do |subscription_migration|
          expect(Events::Stores::Clickhouse::EnrichedStoreMigration::SubscriptionOrchestratorJob)
            .to have_been_enqueued.with(subscription_migration)
        end
      end
    end

    context "when migration is not in checking state" do
      let(:enriched_store_migration) { create(:enriched_store_migration, organization:) }

      it "does nothing" do
        result = service.call

        expect(result.subscription_migration_count).to be_nil
        expect(enriched_store_migration.reload).to be_pending
        expect(Events::Stores::Clickhouse::PreEnrichmentCheckService).not_to have_received(:call)
      end
    end

    context "when PreEnrichmentCheckService fails" do
      before do
        failed_result = Events::Stores::Clickhouse::PreEnrichmentCheckService::Result.new
        failed_result.service_failure!(code: "error", message: "check failed")
        allow(Events::Stores::Clickhouse::PreEnrichmentCheckService)
          .to receive(:call).and_return(failed_result)
      end

      it "transitions the migration to failed" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_failed
        expect(enriched_store_migration.error_message).to include("check failed")
      end
    end

    context "when an exception is raised during subscription migration creation" do
      before do
        allow(EnrichedStoreSubscriptionMigration).to receive(:create!).and_raise(StandardError.new("boom"))
      end

      it "transitions the migration to failed" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_failed
        expect(enriched_store_migration.error_message).to include("boom")
      end
    end
  end
end
