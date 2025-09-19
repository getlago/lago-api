# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService do
  describe "#call" do
    let(:organization) { create(:organization) }
    let(:service) { described_class.new(organization:) }

    before do
      allow(ActiveJob).to receive(:perform_all_later)
    end

    it "enqueues jobs for subscription activities that are not yet enqueued" do
      create_list(:subscription_activity, 3, organization:, enqueued: false)
      create_list(:subscription_activity, 2, organization:, enqueued: true)

      result = service.call

      expect(ActiveJob).to have_received(:perform_all_later).once do |jobs|
        expect(jobs).to all(be_a(UsageMonitoring::ProcessSubscriptionActivityJob))
      end

      expect(result).to be_success
      expect(result.nb_jobs_enqueued).to eq(3)

      expect(organization.subscription_activities.where(enqueued: true).count).to eq(5)
      expect(organization.subscription_activities.where(enqueued: false).count).to eq(0)
    end

    context "when there are no subscription activities to enqueue" do
      it "returns 0 for number of jobs enqueued and does not enqueue any job" do
        create_list(:subscription_activity, 2, organization:, enqueued: true)

        expect(ActiveJob).not_to have_received(:perform_all_later)

        result = service.call

        expect(result).to be_success
        expect(result.nb_jobs_enqueued).to eq(0)
      end
    end

    context "with more than BATCH_SIZE subscription activities" do
      let(:batch_size) { 3 }

      before do
        stub_const("#{described_class}::BATCH_SIZE", batch_size)
      end

      it "processes activities in batches" do
        create_list(:subscription_activity, batch_size + 1, organization:, enqueued: false)

        result = service.call

        expect(ActiveJob).to have_received(:perform_all_later).twice
        expect(result.nb_jobs_enqueued).to eq(batch_size + 1)
      end
    end
  end
end
