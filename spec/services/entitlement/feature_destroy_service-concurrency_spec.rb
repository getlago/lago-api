# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeatureDestroyService do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }

  describe "#call", :premium do
    context "with threads", transaction: false do
      let(:release) { Queue.new }

      before { privilege }

      # Frees a writer left waiting by a failed expectation.
      after { release << true }

      # The writer has inserted the entitlement and its value on the feature and holds its transaction while
      # the delete starts in another connection. The writer sends no webhook, so any plan.updated is the delete's.
      it "waits for a write adding the feature, then discards it and notifies its plan" do
        feature_id = feature.id
        deleter = nil

        allow(Entitlement::EntitlementValue).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
          value = original.call(*args, **kwargs)
          deleter = Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              described_class.call(feature: Entitlement::Feature.find(feature_id))
            end
          end
          release.pop
          value
        end

        writer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Entitlement::PlanEntitlementsUpdateService.call(
              organization: Organization.find(organization.id),
              plan: Plan.find(plan.id),
              entitlements_params: {feature.code => {privilege.code => 10}},
              partial: true,
              send_webhook: false
            )
          end
        end

        sleep 0.05 until deleter || !writer.alive?
        expect(deleter.join(0.5)).to be_nil

        release << true
        expect(writer.join(5)).to eq(writer)
        expect(deleter.join(5)).to eq(deleter)

        expect(writer.value).to be_success
        expect(deleter.value).to be_success
        expect(Entitlement::Entitlement.where(entitlement_feature_id: feature_id).count).to eq(0)
        expect(Entitlement::EntitlementValue.where(entitlement_privilege_id: privilege.id).count).to eq(0)
        expect(SendWebhookJob).to have_been_enqueued.with("plan.updated", plan)
      end
    end
  end
end
