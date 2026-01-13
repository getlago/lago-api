# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::ReEnrichService do
  let(:re_enrich_service) { described_class.new(subscription:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:plan) { subscription.plan }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      properties: {
        billable_metric.field_name => 12
      },
      timestamp: Time.current
    )
  end

  before do
    event
    charge
  end

  describe "#call" do
    it "creates the relevant enriched_events" do
      result = nil

      expect { result = re_enrich_service.call }.to change(EnrichedEvent, :count).by(1)
      expect(result).to be_success
    end

    context "with pre-existing enriched events" do
      before { create_list(:enriched_event, 3, subscription:, event:) }

      it "removes the enriched_events and creates the relevant one" do
        result = nil

        expect { result = re_enrich_service.call }.to change(EnrichedEvent, :count).by(-2)
        expect(result).to be_success
      end
    end
  end
end
