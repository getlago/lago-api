# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Subscriptions::RecurringUsageController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:billable_metric) do
    create(
      :sum_billable_metric,
      :recurring,
      organization:,
      code: "twilio_device",
      field_name: "amount"
    )
  end
  let(:charge) do
    create(
      :standard_charge,
      organization:,
      plan:,
      billable_metric:,
      code: "twilio_device_monthly",
      properties: {
        amount: "1",
        pricing_group_keys: ["device_id"]
      }
    )
  end
  let(:body) do
    {
      recurring_usage: {
        billable_metric_code: billable_metric.code,
        charge_code: charge.code,
        transaction_id: "remove-device-1",
        group: {
          device_id: "device-1"
        }
      }
    }
  end

  before do
    charge
    create(
      :event,
      organization_id: organization.id,
      subscription:,
      code: billable_metric.code,
      timestamp: 2.days.ago,
      properties: {
        "device_id" => "device-1",
        "amount" => "1.15"
      }
    )
    create(
      :event,
      organization_id: organization.id,
      subscription:,
      code: billable_metric.code,
      timestamp: 2.days.ago,
      properties: {
        "device_id" => "device-2",
        "amount" => "2.00"
      }
    )
  end

  describe "POST /api/v1/subscriptions/:external_id/terminate_recurring_usage" do
    subject do
      post_with_token(
        organization,
        "/api/v1/subscriptions/#{subscription.external_id}/terminate_recurring_usage",
        body
      )
    end

    include_examples "requires API permission", "subscription", "write"

    it "creates a compensating event for the targeted recurring group" do
      expect { subject }.to change(Event, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json[:event]).to include(
        transaction_id: "remove-device-1",
        code: billable_metric.code,
        external_subscription_id: subscription.external_id
      )

      event = Event.find_by!(transaction_id: "remove-device-1")
      expect(event.properties).to include(
        "device_id" => "device-1",
        "amount" => "-1.15"
      )
    end

    context "when the group is already inactive" do
      let(:body) do
        {
          recurring_usage: {
            billable_metric_code: billable_metric.code,
            group: {
              device_id: "unknown-device"
            }
          }
        }
      end

      it "returns a validation error" do
        expect { subject }.not_to change(Event, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:group]).to eq(["no_active_recurring_usage"])
      end
    end

    context "when the billable metric is not recurring" do
      before { billable_metric.update!(recurring: false) }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:billable_metric_code]).to eq(["not_recurring"])
      end
    end
  end
end
