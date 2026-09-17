# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SlackNotificationJob do
  let(:audit_log) { create(:cs_admin_audit_log) }
  let(:result) { Admin::SlackNotificationService::Result.new }

  before do
    allow(Admin::SlackNotificationService).to receive(:call!).with(audit_log:).and_return(result)
  end

  it "calls the Slack notification service with the audit log" do
    described_class.perform_now(audit_log.id)

    expect(Admin::SlackNotificationService).to have_received(:call!).with(audit_log:)
  end

  it "retries transient Slack failures" do
    allow(Admin::SlackNotificationService).to receive(:call!)
      .with(audit_log:).and_raise(Admin::SlackNotificationService::DeliveryError, "Slack unavailable")

    expect { described_class.perform_now(audit_log.id) }.to have_enqueued_job(described_class).with(audit_log.id)
  end

  it "stops retrying after five attempts" do
    allow(Admin::SlackNotificationService).to receive(:call!)
      .with(audit_log:).and_raise(Admin::SlackNotificationService::DeliveryError, "Slack unavailable")
    job = described_class.new(audit_log.id)
    job.exception_executions["[Admin::SlackNotificationService::DeliveryError]"] = 4

    expect { job.perform_now }.to raise_error(Admin::SlackNotificationService::DeliveryError)
    expect(described_class).not_to have_been_enqueued
  end
end
