# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ProcessDedicatedOrgsSubscriptionActivitiesJob, job: true do
  describe "#perform" do
    subject { described_class.perform_now }

    let_it_be(:target_organization) { create(:organization) }
    let(:other_organization) { create(:organization) }

    context "when the dedicated org list is empty" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", []) }

      context "when premium", :premium do
        it "does not enqueue any job" do
          subject
          expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued
        end
      end
    end

    context "when the dedicated org list contains the target organization" do
      before { stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [target_organization.id]) }

      context "when freemium" do
        it "does not enqueue any job" do
          create(:subscription_activity, organization: target_organization, enqueued: false)

          subject

          expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued
        end
      end

      context "when premium", :premium do
        context "when the target org has pending subscription activities" do
          before do
            create(:subscription_activity, organization: target_organization, enqueued: false)
            create(:subscription_activity, organization: other_organization, enqueued: false)
          end

          it "enqueues ProcessOrganizationSubscriptionActivitiesJob for target org only" do
            subject
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_been_enqueued.with(target_organization.id).once
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued.with(other_organization.id)
          end
        end

        context "when the target org has no pending subscription activities" do
          it "does not enqueue a job" do
            subject
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued
          end
        end

        context "when the target org only has activities already enqueued" do
          before { create(:subscription_activity, organization: target_organization, enqueued: true) }

          it "does not enqueue a job" do
            subject
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued
          end
        end

        context "when the target org has contract activities waiting" do
          before do
            create(:contract_activity, organization: target_organization)
            create(:contract_activity, organization: other_organization)
          end

          it "enqueues the contract activities job of the target org only" do
            subject
            expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.with(target_organization.id).once
            expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued.with(other_organization.id)
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).not_to have_been_enqueued
          end
        end

        context "when the target org has subscription and contract activities waiting" do
          before do
            create(:subscription_activity, organization: target_organization)
            create(:contract_activity, organization: target_organization)
          end

          it "enqueues the job of each" do
            subject
            expect(UsageMonitoring::ProcessOrganizationSubscriptionActivitiesJob).to have_been_enqueued.with(target_organization.id).once
            expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).to have_been_enqueued.with(target_organization.id).once
          end
        end

        context "when the target org only has contract activities already enqueued" do
          before { create(:contract_activity, organization: target_organization, enqueued: true, enqueued_at: Time.current) }

          it "does not enqueue a job" do
            subject
            expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
          end
        end
      end

      context "when freemium and the target org has contract activities waiting" do
        before { create(:contract_activity, organization: target_organization) }

        it "does not enqueue any job" do
          subject
          expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
        end
      end
    end

    context "when the dedicated org list is empty and contract activities are waiting", :premium do
      before do
        stub_const("Utils::DedicatedWorkerConfig::ORGANIZATION_IDS", [])
        create(:contract_activity, organization: target_organization)
      end

      it "leaves them to the main sweep" do
        subject
        expect(UsageMonitoring::ProcessOrganizationContractActivitiesJob).not_to have_been_enqueued
      end
    end
  end
end
