# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::SubscriptionSerializer do
  subject(:serializer) { described_class.new(subscription, root_name: "subscription", includes: %i[customer plan entitlements]) }

  let(:started_at) { Time.zone.parse("2024-04-23 10:02:03") }
  let(:ending_at) { Time.zone.parse("2024-06-30") }
  let(:subscription) do
    create(:subscription, created_at: started_at, started_at:, ending_at:)
  end

  context "when plan has one minimium commitment" do
    let(:commitment) { create(:commitment, plan: subscription.plan) }

    before { commitment }

    it "serializes the object" do
      travel_to(Time.zone.parse("2024-05-28")) do
        result = JSON.parse(serializer.to_json)

        aggregate_failures do
          expect(result["subscription"]).to include(
            "lago_id" => subscription.id,
            "external_id" => subscription.external_id,
            "lago_customer_id" => subscription.customer_id,
            "external_customer_id" => subscription.customer.external_id,
            "name" => subscription.name,
            "plan_code" => subscription.plan.code,
            "status" => subscription.status,
            "billing_time" => subscription.billing_time,
            "created_at" => "2024-04-23T10:02:03Z",
            "ending_at" => ending_at.iso8601,
            "trial_ended_at" => nil,
            "started_at" => "2024-04-23T10:02:03.000Z",
            "current_billing_period_started_at" => "2024-05-01T00:00:00Z",
            "current_billing_period_ending_at" => "2024-05-31T23:59:59Z"
          )

          expect(result["subscription"]["customer"]["lago_id"]).to be_present
          expect(result["subscription"]["plan"]["lago_id"]).to be_present

          expect(result["subscription"]["plan"]["minimum_commitment"]).to include(
            "lago_id" => commitment.id,
            "plan_code" => commitment.plan.code,
            "invoice_display_name" => commitment.invoice_display_name,
            "amount_cents" => commitment.amount_cents,
            "interval" => commitment.plan.interval,
            "created_at" => commitment.created_at.iso8601,
            "updated_at" => commitment.updated_at.iso8601,
            "taxes" => []
          )
          expect(result["subscription"]["plan"]["minimum_commitment"]).not_to include(
            "commitment_type" => "minimum_commitment"
          )
        end
      end
    end
  end

  context "when plan has no minimium commitment" do
    it "serializes the object" do
      travel_to(Time.zone.parse("2024-05-28")) do
        result = JSON.parse(serializer.to_json)

        aggregate_failures do
          expect(result["subscription"]).to include(
            "lago_id" => subscription.id,
            "external_id" => subscription.external_id,
            "lago_customer_id" => subscription.customer_id,
            "external_customer_id" => subscription.customer.external_id,
            "name" => subscription.name,
            "plan_code" => subscription.plan.code,
            "status" => subscription.status,
            "billing_time" => subscription.billing_time,
            "created_at" => started_at.iso8601,
            "ending_at" => ending_at.iso8601,
            "trial_ended_at" => nil,
            "current_billing_period_started_at" => "2024-05-01T00:00:00Z",
            "current_billing_period_ending_at" => "2024-05-31T23:59:59Z"
          )

          expect(result["subscription"]["customer"]["lago_id"]).to be_present
          expect(result["subscription"]["plan"]["minimum_commitment"]).to be_nil
        end
      end
    end
  end

  context "when including usage threshold" do
    subject(:serializer) do
      described_class.new(
        subscription,
        root_name: "subscription",
        includes: %i[usage_threshold],
        usage_threshold:
      )
    end

    let(:usage_threshold) { create(:usage_threshold, plan: subscription.plan) }

    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      expect(result["subscription"]["usage_threshold"]).to be_present
    end
  end

  context "when terminated with credit note" do
    let(:plan) { create(:plan, :pay_in_advance) }
    let(:subscription) { create(:subscription, :terminated, plan:, on_termination_credit_note: :credit) }

    it "serializes the object" do
      result = JSON.parse(serializer.to_json)

      expect(result["subscription"]["on_termination_credit_note"]).to eq("credit")
      expect(result["subscription"]["on_termination_invoice"]).to eq("generate")
      expect(result["subscription"]["terminated_at"]).to be_present
      expect(result["subscription"]["status"]).to eq("terminated")
    end
  end

  context "when terminated with skip invoice" do
    let(:subscription) { create(:subscription, :terminated, on_termination_invoice: :skip) }

    it "serializes the object with skip invoice behavior" do
      result = JSON.parse(serializer.to_json)

      expect(result["subscription"]["on_termination_invoice"]).to eq("skip")
      expect(result["subscription"]["terminated_at"]).to be_present
      expect(result["subscription"]["status"]).to eq("terminated")
    end
  end

  context "when subscription has entitlements" do
    let(:feature) { create(:feature, organization: subscription.organization, code: "seats", name: "Seats", description: "Nb users") }
    let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
    let(:plan_entitlement) { create(:entitlement, feature:, plan: subscription.plan) }
    let(:plan_entitlement_value) { create(:entitlement_value, entitlement: plan_entitlement, privilege:, value: 12) }
    let(:sub_entitlement) { create(:entitlement, feature:, plan: nil, subscription:) }
    let(:sub_entitlement_value) { create(:entitlement_value, entitlement: sub_entitlement, privilege:, value: 99) }

    before {
      plan_entitlement_value
      sub_entitlement_value
    }

    it "serializes the entitlements" do
      result = JSON.parse(serializer.to_json)
      expect(result["subscription"]["entitlements"].count).to eq 1
      expect(result["subscription"]["entitlements"].first).to eq({
        "code" => "seats",
        "name" => "Seats",
        "description" => "Nb users",
        "privileges" => [
          {
            "code" => "max",
            "name" => nil,
            "value" => 99,
            "plan_value" => 12,
            "override_value" => 99,
            "config" => {},
            "value_type" => "integer"
          }
        ],
        "overrides" => {"max" => 99}
      })
    end
  end

  context "when subscription has fixed charges" do
    let(:plan) { create(:plan) }
    let(:fixed_charge) { create(:fixed_charge, plan:) }
    let(:subscription) { create(:subscription, plan:) }

    before { fixed_charge }

    it "does not serialize the fixed charges" do
      result = JSON.parse(serializer.to_json)
      expect(result["subscription"]["plan"]["fixed_charges"]).to be_nil
    end
  end
end
