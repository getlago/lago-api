# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::StoreFactory do
  subject(:store_instance) { described_class.new_instance(organization:, current_usage:, **arguments) }

  let(:organization) { create(:organization, clickhouse_events_store:) }
  let(:clickhouse_events_store) { false }
  let(:current_usage) { false }

  let(:arguments) do
    time = Time.current

    {
      subscription: create(:subscription, organization:),
      boundaries: {
        from_datetime: time.beginning_of_month,
        to_datetime: time.end_of_month,
        period_duration: time.end_of_month.day
      },
      code: "some_bm_code",
      filters: {}
    }
  end

  describe "#new_instance" do
    it "returns an instance of a Postgres store" do
      expect(store_instance).to be_a(Events::Stores::PostgresStore)
    end

    context "when clickhouse is enabled" do
      around do |example|
        previous_value = ENV["LAGO_CLICKHOUSE_ENABLED"]
        ENV["LAGO_CLICKHOUSE_ENABLED"] = "true"
        example.run
        ENV["LAGO_CLICKHOUSE_ENABLED"] = previous_value
      end

      it "returns an instance of a Postgres store" do
        expect(store_instance).to be_a(Events::Stores::PostgresStore)
      end

      context "when organization has the clickhoise flag" do
        let(:clickhouse_events_store) { true }

        it "returns an instance of a Clickhouse store" do
          expect(store_instance).to be_a(Events::Stores::ClickhouseStore)
        end

        context "when current usage and clickhouse_live_aggregation", :premium do
          let(:current_usage) { true }

          before do
            organization.premium_integrations << "clickhouse_live_aggregation"
            organization.save!
          end

          it "returns an instance of an Aggregated Clickhouse store" do
            expect(store_instance).to be_a(Events::Stores::AggregatedClickhouseStore)
          end
        end
      end
    end
  end
end
