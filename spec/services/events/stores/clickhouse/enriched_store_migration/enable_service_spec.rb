# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::EnrichedStoreMigration::EnableService do
  subject(:service) { described_class.new(enriched_store_migration:) }

  let(:organization) { create(:organization, pre_filter_events: false) }
  let(:enriched_store_migration) { create(:enriched_store_migration, :enabling, organization:) }

  describe "#call" do
    context "when all subscription migrations are completed" do
      before do
        create(:enriched_store_subscription_migration, :completed,
          enriched_store_migration:,
          organization:,
          subscription: create(:subscription, organization:))
      end

      it "enables the feature flag and pre_filter_events" do
        freeze_time do
          service.call

          organization.reload
          expect(organization.feature_flag_enabled?(:enriched_events_aggregation)).to be true
          expect(organization.pre_filter_events).to be true

          enriched_store_migration.reload
          expect(enriched_store_migration).to be_completed
          expect(enriched_store_migration.completed_at).to eq(Time.current)
        end
      end
    end

    context "when not all subscription migrations are completed" do
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

      it "fails the migration and does not flip the flag" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_failed
        expect(enriched_store_migration.error_message).to include("not all subscription migrations are completed")

        organization.reload
        expect(organization.feature_flag_enabled?(:enriched_events_aggregation)).to be false
        expect(organization.pre_filter_events).to be false
      end
    end

    context "when migration is not in enabling state" do
      let(:enriched_store_migration) { create(:enriched_store_migration, :processing, organization:) }

      it "does nothing" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_processing
        organization.reload
        expect(organization.feature_flag_enabled?(:enriched_events_aggregation)).to be false
      end
    end

    context "when an exception is raised" do
      before do
        create(:enriched_store_subscription_migration, :completed,
          enriched_store_migration:,
          organization:,
          subscription: create(:subscription, organization:))

        allow(enriched_store_migration).to receive(:organization).and_return(organization)
        allow(organization).to receive(:enable_feature_flag!).and_raise(StandardError.new("Unknown feature flag: flag"))
      end

      it "fails the migration" do
        service.call

        enriched_store_migration.reload
        expect(enriched_store_migration).to be_failed
        expect(enriched_store_migration.error_message).to include("Unknown feature flag: flag")
      end
    end
  end
end
