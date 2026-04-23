# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::EnrichedStoreMigration::OrchestratorService do
  subject(:service) { described_class.new(enriched_store_migration:) }

  let(:organization) { create(:organization) }

  before do
    allow(Events::Stores::Clickhouse::EnrichedStoreMigration::CheckJob).to receive(:perform_later)
    allow(Events::Stores::Clickhouse::EnrichedStoreMigration::EnableJob).to receive(:perform_later)
  end

  describe "#call" do
    context "when status is pending" do
      let(:enriched_store_migration) { create(:enriched_store_migration, organization:) }

      it "transitions to checking, sets started_at and enqueues CheckJob" do
        freeze_time do
          service.call

          enriched_store_migration.reload
          expect(enriched_store_migration).to be_checking
          expect(enriched_store_migration.started_at).to eq(Time.current)
          expect(Events::Stores::Clickhouse::EnrichedStoreMigration::CheckJob)
            .to have_received(:perform_later).with(enriched_store_migration)
        end
      end
    end

    context "when status is processing and all subscription migrations completed" do
      let(:enriched_store_migration) { create(:enriched_store_migration, :processing, organization:) }

      before do
        create(:enriched_store_subscription_migration, :completed,
          enriched_store_migration:,
          organization:,
          subscription: create(:subscription, organization:))
      end

      it "transitions to enabling and enqueues EnableJob" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_enabling
        expect(Events::Stores::Clickhouse::EnrichedStoreMigration::EnableJob)
          .to have_received(:perform_later).with(enriched_store_migration)
      end
    end

    context "when status is processing but not all subscription migrations completed" do
      let(:enriched_store_migration) { create(:enriched_store_migration, :processing, organization:) }

      before do
        create(:enriched_store_subscription_migration, :completed,
          enriched_store_migration:,
          organization:,
          subscription: create(:subscription, organization:))
        create(:enriched_store_subscription_migration, :reprocessing,
          enriched_store_migration:,
          organization:,
          subscription: create(:subscription, organization:))
      end

      it "stays in processing and does not enqueue EnableJob" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_processing
        expect(Events::Stores::Clickhouse::EnrichedStoreMigration::EnableJob)
          .not_to have_received(:perform_later)
      end
    end

    context "when status is processing with no subscription migrations" do
      let(:enriched_store_migration) { create(:enriched_store_migration, :processing, organization:) }

      it "stays in processing" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_processing
        expect(Events::Stores::Clickhouse::EnrichedStoreMigration::EnableJob)
          .not_to have_received(:perform_later)
      end
    end

    context "when in a non-actionable status" do
      let(:enriched_store_migration) { create(:enriched_store_migration, :enabling, organization:) }

      it "is a no-op" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_enabling
        expect(Events::Stores::Clickhouse::EnrichedStoreMigration::CheckJob).not_to have_received(:perform_later)
        expect(Events::Stores::Clickhouse::EnrichedStoreMigration::EnableJob).not_to have_received(:perform_later)
      end
    end
  end
end
