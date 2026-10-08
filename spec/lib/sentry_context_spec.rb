# frozen_string_literal: true

require "rails_helper"

RSpec.describe SentryContext do
  before do
    allow(Sentry).to receive(:set_tags)
    allow(Sentry).to receive(:set_user)
    allow(Sentry).to receive(:add_breadcrumb)
  end

  describe ".tag_job" do
    subject(:tag_job) { described_class.tag_job(job) }

    let(:customer) { create(:customer) }
    let(:job_class) do
      Class.new(ApplicationJob) do
        def perform(*, **)
        end
      end
    end
    let(:job) { job_class.new(*arguments) }
    let(:arguments) { [customer, "plain"] }

    it "tags the records and their organization" do
      tag_job

      expect(Sentry).to have_received(:set_tags)
        .with(job_executions: 0, customer_id: customer.id, organization_id: customer.organization_id)
    end

    context "with records passed as keyword arguments" do
      let(:wallet) { create(:wallet, customer:) }
      let(:arguments) { [customer, {wallet_ids: [], wallet:}] }

      it "tags every record" do
        tag_job

        expect(Sentry).to have_received(:set_tags).with(
          job_executions: 0,
          customer_id: customer.id,
          wallet_id: wallet.id,
          organization_id: customer.organization_id
        )
      end
    end

    context "with an organization argument" do
      let(:organization) { create(:organization) }
      let(:arguments) { [organization] }

      it "tags the organization id" do
        tag_job

        expect(Sentry).to have_received(:set_tags)
          .with(job_executions: 0, organization_id: organization.id)
      end
    end

    context "without record arguments" do
      let(:arguments) { ["plain", 1] }

      it "tags only the executions" do
        tag_job

        expect(Sentry).to have_received(:set_tags).with(job_executions: 0)
      end
    end
  end

  describe ".tag_request" do
    let(:membership) { create(:membership) }

    it "tags the organization and sets the user" do
      described_class.tag_request(organization: membership.organization, user: membership.user)

      expect(Sentry).to have_received(:set_tags).with(organization_id: membership.organization_id)
      expect(Sentry).to have_received(:set_user).with(id: membership.user_id)
    end

    context "without organization nor user" do
      it "sets nothing" do
        described_class.tag_request(organization: nil)

        expect(Sentry).not_to have_received(:set_tags)
        expect(Sentry).not_to have_received(:set_user)
      end
    end
  end

  describe ".breadcrumb" do
    it "adds a breadcrumb with the data" do
      described_class.breadcrumb("clickhouse.retry", "failed", level: "warning", attempt: 1)

      expect(Sentry).to have_received(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb).to have_attributes(
          category: "clickhouse.retry",
          message: "failed",
          level: "warning",
          data: {attempt: 1}
        )
      end
    end
  end

  describe ".add_organization_context" do
    subject(:add_organization_context) { described_class.add_organization_context(event) }

    let(:organization) { create(:organization, name: "Acme") }
    let(:event) { instance_double(Sentry::ErrorEvent, tags:, contexts: {}) }
    let(:tags) { {organization_id: organization.id} }

    it "adds the organization name" do
      expect(add_organization_context.contexts[:organization]).to eq(id: organization.id, name: "Acme")
    end

    context "with an unknown organization id" do
      let(:tags) { {organization_id: SecureRandom.uuid} }

      it "leaves the event unchanged" do
        expect(add_organization_context.contexts).to eq({})
      end
    end

    context "without organization tag" do
      let(:tags) { {} }

      it "leaves the event unchanged" do
        expect(add_organization_context.contexts).to eq({})
      end
    end
  end
end
