# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventsQuery do
  subject(:events_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:event) { create(:event, timestamp: 1.day.ago.to_date, organization:) }

  before { event }

  describe "call" do
    it "returns a list of events" do
      result = events_query.call

      expect(result).to be_success
      expect(result.events.count).to eq(1)
      expect(result.events).to eq([event])
    end

    context "with pagination" do
      let(:pagination) { {page: 2, limit: 10} }

      it "applies the pagination" do
        result = events_query.call

        expect(result).to be_success
        expect(result.events.count).to eq(0)
        expect(result.events.current_page).to eq(2)
      end
    end

    context "with code filter" do
      let(:event2) { create(:event, organization:) }
      let(:filters) { {code: event.code} }

      before { event2 }

      it "applies the filter" do
        result = events_query.call

        expect(result).to be_success
        expect(result.events.count).to eq(1)
      end
    end

    context "with external subscription id filter" do
      let(:event2) { create(:event, organization:) }
      let(:filters) { {external_subscription_id: event.external_subscription_id} }

      before { event2 }

      it "applies the filter" do
        result = events_query.call

        expect(result).to be_success
        expect(result.events.count).to eq(1)
      end
    end

    context "with timestamp filters" do
      let(:filters) {
        {
          timestamp_from: 2.days.ago.iso8601.to_date.to_s,
          timestamp_to: Date.tomorrow.iso8601.to_date.to_s
        }
      }

      it "applies the filter" do
        result = events_query.call

        expect(result).to be_success
        expect(result.events.count).to eq(1)
      end
    end

    context "with timestamp_from_started filter" do
      let(:started_at) { 1.day.ago }
      let(:subscription) { create(:subscription, organization:, started_at:) }

      let(:event_before) { create(:event, organization:, timestamp: started_at - 1.second, external_subscription_id: subscription.external_id) }
      let(:event_after) { create(:event, organization:, timestamp: started_at + 1.second, external_subscription_id: subscription.external_id) }
      let(:event_other_sub) { create(:event, organization:, timestamp: started_at + 1.minute) }
      let(:old_event_other_sub) { create(:event, organization:, timestamp: started_at - 2.years) }

      before do
        event_before
        event_after
        event_other_sub
        old_event_other_sub
      end

      context "when timestamp_from_started_at filters is true" do
        let(:filters) do
          {
            timestamp_from_started_at: true,
            external_subscription_id: subscription.external_id
          }
        end

        it "returns only events after started_at" do
          result = events_query.call

          expect(result).to be_success
          expect(result.events.ids).to contain_exactly(event_after.id)
        end
      end

      context "when timestamp_from is also set" do
        let(:filters) do
          {
            timestamp_from: started_at - 1.year,
            timestamp_from_started_at: true,
            external_subscription_id: subscription.external_id
          }
        end

        it "uses subscription started_at" do
          result = events_query.call

          expect(result).to be_failure
          expect(result.error.messages).to eq({timestamp_from: ["cannot be used with timestamp_from_started_at"]})
        end

        context "when subscription_external_id is missing" do
          let(:filters) do
            {
              timestamp_from: started_at - 1.year,
              timestamp_from_started_at: true
            }
          end

          it "returns an error" do
            result = events_query.call
            expect(result).to be_failure
            expect(result.error.messages).to eq({
              timestamp_from: ["cannot be used with timestamp_from_started_at"],
              external_subscription_id: ["required with timestamp_from_started_at"]
            })
          end
        end
      end

      context "when subscription_external_id is missing" do
        let(:filters) do
          {
            timestamp_from_started_at: true
          }
        end

        it "ignores timestamp_from_started_at" do
          result = events_query.call
          expect(result).to be_failure
          expect(result.error.messages).to eq({external_subscription_id: ["required with timestamp_from_started_at"]})
        end
      end
    end
  end

  describe "event model" do
    let(:model) { events_query.send :event_model }

    context "when organization is using postgres" do
      let(:organization) { create(:organization, clickhouse_events_store: false) }

      it { expect(model).to eq(Event) }

      context "when `enriched` filter is true" do
        let(:filters) { {enriched: true} }

        it { expect(model).to eq(Event) }
      end
    end

    context "when organization is not using clickhouse" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it { expect(model).to eq(Clickhouse::EventsRaw) }

      context "when `enriched` filter is true" do
        let(:filters) { {enriched: true} }

        it { expect(model).to eq(Clickhouse::EventsEnriched) }
      end
    end
  end
end
